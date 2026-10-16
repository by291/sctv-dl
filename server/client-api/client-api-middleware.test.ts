import { once } from 'node:events'
import { createServer } from 'node:http'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { clientApiMiddleware } from './client-api-middleware.ts'

import type { Server } from 'node:http'
import type { AddressInfo } from 'node:net'

const httpFetch = globalThis.fetch
let server: Server
let origin: string
let errors: ReturnType<typeof vi.spyOn>

beforeEach(async () => {
  errors = vi.spyOn(console, 'error').mockImplementation(() => {})
  server = createServer((request, response) => {
    clientApiMiddleware(request, response, () => response.writeHead(404).end())
  })
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
})

afterEach(async () => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
  server.closeAllConnections()
  await new Promise<void>((resolve) => server.close(() => resolve()))
})

describe('normalized client API', () => {
  it.each([
    [
      '/client-api/v1/programmes/9007199254740992/dates',
      'https://gw.scgchc.com/app/v1/programs/9007199254740992/dates/list',
      [{ id: '2', date: '2026-10-16' }],
      [{ id: '2', date: '2026-10-16' }],
    ],
    [
      '/client-api/v1/programmes/1/dates/9007199254740992/contents',
      'https://gw.scgchc.com/app/v1/programs/1/dates/9007199254740992/contents/list',
      [{ id: '3', title: 'News', videoStandard: '/news.mp4' }],
      [
        {
          id: '3',
          title: 'News',
          cover: null,
          video: null,
          smoothVideo: 'https://fscgc.scgchc.com/news.mp4',
          publishedAt: null,
        },
      ],
    ],
  ])('dispatches %s with intact string IDs', async (path, upstreamUrl, data, expected) => {
    vi.stubGlobal('fetch', async (url: string) => {
      if (url !== upstreamUrl) {
        throw new Error('Unexpected upstream route')
      }

      return Response.json({ rs: 200, data })
    })

    const response = await httpFetch(`${origin}${path}`)

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ data: expected })
  })

  it('prepares playback with a validated source and actual fallback quality', async () => {
    vi.stubGlobal('fetch', async (url: string | URL | Request) =>
      Response.json({
        rs: 200,
        data: String(url).includes('/contents/')
          ? [{ id: '3', title: 'News', videoStandard: '/news.mp4' }]
          : [{ id: '2', date: '2026-10-16' }],
      }),
    )

    const response = await httpFetch(`${origin}/client-api/v1/playback/prepare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ programmeId: '1', dateId: '2', contentId: '3', quality: 'standard' }),
    })

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      data: {
        id: expect.any(String),
        selectedQuality: 'smooth',
        sources: [{ quality: 'smooth', url: 'https://fscgc.scgchc.com/news.mp4' }],
      },
    })
  })

  it('maps unavailable broadcasts to a not-found response', async () => {
    vi.stubGlobal('fetch', async () => Response.json({ rs: 200, data: [] }))

    const response = await httpFetch(`${origin}/client-api/v1/playback/prepare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ programmeId: '1', dateId: '2', contentId: '3', quality: 'standard' }),
    })

    expect(response.status).toBe(404)
    expect(await response.json()).toMatchObject({ error: { code: 'not-found' } })
    expect(errors).not.toHaveBeenCalled()
  })

  it.each([
    ['/client-api/v1/missing', 'GET', undefined, 404],
    ['/client-api/v1/programmes/invalid/dates', 'GET', undefined, 400],
    ['/client-api/v1/programmes/invalid/dates', 'POST', undefined, 405],
    ['/client-api/v1/programmes/1/dates/invalid/contents', 'GET', undefined, 400],
    ['/client-api/v1/playback/prepare', 'HEAD', undefined, 405],
    [
      '/client-api/v1/playback/prepare',
      'POST',
      JSON.stringify({
        programmeId: '1',
        dateId: '2',
        contentId: '3',
        quality: 'standard',
        url: 'https://example.com/file.mp4',
      }),
      400,
    ],
  ] as const)(
    'rejects invalid route or input %s before upstream work',
    async (path, method, body, status) => {
      const upstream = vi.fn()
      vi.stubGlobal('fetch', upstream)

      const response = await httpFetch(`${origin}${path}`, {
        method,
        body,
        headers: { 'Content-Type': 'application/json' },
      })

      expect(response.status).toBe(status)
      expect(response.headers.get('content-type')).toContain('application/json')
      if (status === 405) {
        expect(response.headers.get('allow')).toBe(path.endsWith('/prepare') ? 'POST' : 'GET, HEAD')
      }

      expect(upstream).not.toHaveBeenCalled()
      expect(errors).not.toHaveBeenCalled()
    },
  )

  it('logs the original upstream failure once without exposing it in the response', async () => {
    const cause = new Error('Private connection diagnostic')
    vi.stubGlobal('fetch', async () => {
      throw cause
    })

    const response = await httpFetch(`${origin}/client-api/v1/programmes?private=value`)

    expect(response.status).toBe(502)
    expect(await response.text()).not.toContain('Private connection diagnostic')
    expect(errors).toHaveBeenCalledExactlyOnceWith(
      expect.stringContaining('GET /client-api/v1/programmes'),
      expect.objectContaining({ cause }),
    )
    expect(errors.mock.calls[0]?.[0]).not.toContain('private=value')
  })

  it('cancels upstream work without logging an error when the caller disconnects', async () => {
    let started!: (signal: AbortSignal) => void
    const upstreamStarted = new Promise<AbortSignal>((resolve) => {
      started = resolve
    })
    vi.stubGlobal('fetch', (_target: string, options: RequestInit) => {
      const signal = options.signal!
      started(signal)

      return new Promise<Response>((_resolve, reject) => {
        signal.addEventListener('abort', () => reject(signal.reason), { once: true })
      })
    })
    const controller = new AbortController()
    const response = httpFetch(`${origin}/client-api/v1/programmes`, {
      signal: controller.signal,
    }).catch(() => null)
    const upstreamSignal = await upstreamStarted

    controller.abort()
    await response

    await vi.waitFor(() => expect(upstreamSignal.aborted).toBe(true))
    expect(errors).not.toHaveBeenCalled()
  })
})
