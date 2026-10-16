import { createServer, IncomingMessage, ServerResponse } from 'node:http'
import { Socket } from 'node:net'
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { once } from 'node:events'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { z } from 'zod'

import { createHttpApp } from './http-app.ts'
import { preparedDownloadsSchema } from '../shared/contracts/downloads.ts'
import { clientApiMiddleware } from './client-api/client-api-middleware.ts'

import type { AddressInfo } from 'node:net'
import type { Server } from 'node:http'

const httpFetch = globalThis.fetch
let directory: string
let server: Server
let origin: string

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), 'sctv-server-'))
  await mkdir(join(directory, 'assets'))
  await writeFile(join(directory, 'index.html'), '<html>Programme library</html>')
  await writeFile(join(directory, 'assets', 'app-12345678.js'), 'console.log("app")')
  await writeFile(join(directory, '.env'), 'PRIVATE_VALUE=secret')

  server = createServer(createHttpApp(directory))
  server.listen(0, '127.0.0.1')
  await once(server, 'listening')
  origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
})

afterEach(async () => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
  if (server?.listening) {
    server.closeAllConnections()
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()))
    })
  }

  await rm(directory, { recursive: true, force: true })
})

describe('production HTTP app', () => {
  it('rejects malformed request targets without throwing outside the request handler', () => {
    const socket = new Socket()
    const request = new IncomingMessage(socket)
    request.url = '//['
    request.method = 'GET'
    const response = new ServerResponse(request)

    try {
      expect(() => clientApiMiddleware(request, response, () => {})).not.toThrow()
      expect(response.statusCode).toBe(400)
    } finally {
      socket.destroy()
    }
  })

  it('allows sequential preparation requests whose individual headers arrive within the deadline', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    let firstStarted!: () => void
    let secondStarted!: () => void
    const first = new Promise<void>((resolve) => {
      firstStarted = resolve
    })
    const second = new Promise<void>((resolve) => {
      secondStarted = resolve
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation((url, options) => {
        const isContents = String(url).includes('/contents/')
        ;(isContents ? secondStarted : firstStarted)()

        return new Promise<Response>((resolve, reject) => {
          const timer = setTimeout(
            () =>
              resolve(
                Response.json({
                  rs: 200,
                  data: isContents
                    ? [{ id: '3', title: 'News', video: '/news.mp4' }]
                    : [{ id: '2', date: '2026-10-16' }],
                }),
              ),
            12_000,
          )
          options.signal.addEventListener(
            'abort',
            () => {
              clearTimeout(timer)
              reject(options.signal.reason)
            },
            { once: true },
          )
        })
      }),
    )
    const responsePromise = httpFetch(`${origin}/client-api/v1/downloads/prepare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        programmeId: '1',
        dateId: '2',
        contentIds: ['3'],
        quality: 'standard',
      }),
    })
    await first
    await vi.advanceTimersByTimeAsync(12_000)
    await second
    await vi.advanceTimersByTimeAsync(12_000)
    const response = await responsePromise
    expect(response.status).toBe(200)
    expect(
      z.object({ data: preparedDownloadsSchema }).parse(await response.json()).data.files,
    ).toHaveLength(1)
  })

  it('serves normalized programme data without exposing upstream envelopes', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation(
        async () =>
          new Response(
            JSON.stringify({
              rs: 200,
              data: { records: [{ id: '9007199254740992', name: 'News', cover: '/cover.jpg' }] },
            }),
          ),
      ),
    )
    const response = await httpFetch(`${origin}/client-api/v1/programmes`)
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      data: [{ id: '9007199254740992', name: 'News', cover: 'https://kscgc.sctv.com/cover.jpg' }],
    })
    const head = await httpFetch(`${origin}/client-api/v1/programmes`, { method: 'HEAD' })
    expect(head.status).toBe(200)
    expect(await head.text()).toBe('')
  })

  it('prepares files on the backend using one guest identity for the entire request', async () => {
    const identities: string[] = []
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation(async (url, options) => {
        identities.push(options.headers.deviceId)
        const data = String(url).includes('/contents/')
          ? [{ id: '3', title: 'News', video: '/news.mp4' }]
          : [{ id: '2', date: '2026-10-16' }]

        return new Response(JSON.stringify({ rs: 200, data }))
      }),
    )
    const response = await httpFetch(`${origin}/client-api/v1/downloads/prepare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        programmeId: '1',
        dateId: '2',
        contentIds: ['3', '4'],
        quality: 'smooth',
      }),
    })
    expect(response.status).toBe(200)
    const payload = z.object({ data: preparedDownloadsSchema }).parse(await response.json())
    expect(payload.data.files).toEqual([
      {
        contentId: '3',
        title: 'News',
        url: 'https://fscgc.scgchc.com/news.mp4',
        filename: '2026-10-16_News_标准.mp4',
        quality: 'standard',
      },
    ])
    expect(payload.data.usedFallback).toBe(true)
    expect(payload.data.failures).toHaveLength(1)
    expect(identities).toHaveLength(2)
    expect(identities[0]).toBe(identities[1])
    expect(response.headers.get('set-cookie')).toContain('Path=/client-api')
  })

  it.each([
    ['/client-api/v1/programmes/nope/dates', 'GET', undefined, 400],
    ['/client-api/v1/missing', 'GET', undefined, 404],
    ['/client-api/v1/programmes', 'DELETE', undefined, 405],
    ['/client-api/v1/downloads/prepare', 'POST', '{bad', 400],
    ['/client-api/v1/downloads/prepare', 'POST', ' '.repeat(16_385), 400],
    [
      '/client-api/v1/downloads/prepare',
      'POST',
      JSON.stringify({
        programmeId: '1',
        dateId: '2',
        contentIds: Array.from({ length: 101 }, (_, i) => String(i)),
        quality: 'standard',
      }),
      400,
    ],
  ] as const)('rejects invalid client request %s with %s', async (path, method, body, status) => {
    const upstream = vi.fn()
    vi.stubGlobal('fetch', upstream)
    const response = await httpFetch(`${origin}${path}`, {
      method,
      body,
      headers: { 'Content-Type': 'application/json' },
    })
    expect(response.status).toBe(status)
    expect(response.headers.get('content-type')).toContain('application/json')
    expect(upstream).not.toHaveBeenCalled()
  })

  it('rejects upstream redirects instead of following them', async () => {
    const upstream = vi
      .fn()
      .mockResolvedValue(
        new Response(null, { status: 302, headers: { Location: 'https://example.com' } }),
      )
    vi.stubGlobal('fetch', upstream)
    const response = await httpFetch(`${origin}/client-api/v1/programmes`)
    expect(response.status).toBe(502)
    expect(upstream).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ redirect: 'manual' }),
    )
  })

  it('serves the frontend for direct programme navigation', async () => {
    const response = await httpFetch(`${origin}/programmes/1`)

    expect(response.status).toBe(200)
    expect(response.headers.get('content-type')).toContain('text/html')
    expect(response.headers.get('cache-control')).toBe('no-cache')
    expect(await response.text()).toBe('<html>Programme library</html>')
  })

  it('caches built assets and supports conditional requests', async () => {
    const response = await httpFetch(`${origin}/assets/app-12345678.js`)
    const etag = response.headers.get('etag')

    expect(await response.text()).toBe('console.log("app")')
    expect(response.headers.get('cache-control')).toContain('immutable')
    expect(response.headers.get('x-content-type-options')).toBe('nosniff')
    expect(etag).toBeTruthy()

    const cached = await httpFetch(`${origin}/assets/app-12345678.js`, {
      headers: { 'If-None-Match': etag! },
    })
    expect(cached.status).toBe(304)
  })

  it.each(['/assets/missing.js', '/assets/missing', '/.env', '/.git/config', '/media/missing'])(
    'returns 404 instead of frontend HTML for %s',
    async (path) => {
      const response = await httpFetch(`${origin}${path}`)

      expect(response.status).toBe(404)
      expect(await response.text()).not.toContain('secret')
    },
  )

  it('rejects writes instead of serving the frontend', async () => {
    const response = await httpFetch(origin, { method: 'POST' })

    expect(response.status).toBe(405)
    expect(response.headers.get('allow')).toBe('GET, HEAD')
  })

  it('ignores malformed ranges on frontend assets and keeps serving requests', async () => {
    const response = await httpFetch(`${origin}/assets/app-12345678.js`, {
      headers: { Range: 'bytes=10-1' },
      signal: AbortSignal.timeout(1_000),
    })

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('console.log("app")')
    expect((await httpFetch(`${origin}/healthz`)).status).toBe(200)
  })

  it('checks health without calling the upstream service', async () => {
    const upstream = vi.fn()
    vi.stubGlobal('fetch', upstream)
    const response = await httpFetch(`${origin}/healthz`)

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ status: 'ok' })
    expect(upstream).not.toHaveBeenCalled()

    const head = await httpFetch(`${origin}/healthz`, { method: 'HEAD' })
    expect(head.status).toBe(200)
    expect(await head.text()).toBe('')
  })

  it('serves metadata through the same port', async () => {
    const upstream = vi
      .fn()
      .mockResolvedValue(
        new Response('{"data":[]}', { headers: { 'Content-Type': 'application/json' } }),
      )
    vi.stubGlobal('fetch', upstream)
    const response = await httpFetch(`${origin}/api/app/v1/programs?page=7`)

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ data: [] })
    expect(upstream).toHaveBeenCalledWith(
      new URL('https://gw.scgchc.com/app/v1/programs?page=0&size=100'),
      expect.objectContaining({ method: 'GET' }),
    )
  })

  it('retains media ranges and download filenames', async () => {
    const upstream = vi.fn().mockResolvedValue(
      new Response('abc', {
        status: 206,
        headers: {
          'Content-Type': 'video/mp4',
          'Content-Length': '3',
          'Content-Range': 'bytes 0-2/100',
          'Accept-Ranges': 'bytes',
        },
      }),
    )
    vi.stubGlobal('fetch', upstream)
    const parameters = new URLSearchParams({
      url: 'https://fscgc.scgchc.com/NewsMedia/clip.mp4',
      download: '1',
      filename: '节目.mp4',
    })
    const response = await httpFetch(`${origin}/media?${parameters}`, {
      headers: { Range: 'bytes=0-2', 'If-Range': '"clip-etag"' },
    })

    expect(response.status).toBe(206)
    expect(response.headers.get('content-range')).toBe('bytes 0-2/100')
    expect(response.headers.get('content-disposition')).toContain(
      "filename*=UTF-8''%E8%8A%82%E7%9B%AE.mp4",
    )
    expect(await response.text()).toBe('abc')
    expect(upstream).toHaveBeenCalledWith(
      new URL('https://fscgc.scgchc.com/NewsMedia/clip.mp4'),
      expect.objectContaining({
        headers: expect.objectContaining({
          Referer: 'https://scgc.video.play/',
          Range: 'bytes=0-2',
          'If-Range': '"clip-etag"',
        }),
      }),
    )
  })

  it('starts delivering media before the upstream finishes', async () => {
    let finish: () => void
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('first'))
        finish = () => {
          controller.enqueue(new TextEncoder().encode('last'))
          controller.close()
        }
      },
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response(body, { headers: { 'Content-Type': 'video/mp4' } })),
    )

    const response = await httpFetch(`${origin}/media?url=https://fscgc.scgchc.com/clip.mp4`, {
      signal: AbortSignal.timeout(2_000),
    })
    const reader = response.body!.getReader()
    const first = await reader.read()

    expect(new TextDecoder().decode(first.value)).toBe('first')
    finish!()
    expect(new TextDecoder().decode((await reader.read()).value)).toBe('last')
    expect((await reader.read()).done).toBe(true)
  })

  it.each(['/api/not-a-programme-endpoint', '/media?url=https://example.com/clip.mp4'])(
    'rejects unsupported proxy targets at %s',
    async (path) => {
      const upstream = vi.fn()
      vi.stubGlobal('fetch', upstream)
      const response = await httpFetch(`${origin}${path}`)

      expect(response.status).toBe(400)
      expect(upstream).not.toHaveBeenCalled()
    },
  )
})
