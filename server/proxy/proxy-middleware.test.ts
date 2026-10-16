import { once } from 'node:events'
import { createServer } from 'node:http'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { proxyMiddleware } from './proxy-middleware.ts'

import type { Server } from 'node:http'
import type { AddressInfo } from 'node:net'

const httpFetch = globalThis.fetch
let server: Server
let origin: string

beforeEach(async () => {
  server = createServer((request, response) => {
    proxyMiddleware(request, response, () => response.writeHead(404).end())
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

describe('proxy transport contracts', () => {
  it('logs a connection failure once while retaining the proxy error response', async () => {
    const cause = new Error('Connection diagnostic')
    const errors = vi.spyOn(console, 'error').mockImplementation(() => {})
    vi.stubGlobal('fetch', async () => {
      throw cause
    })

    const response = await httpFetch(`${origin}/media?url=https://fscgc.scgchc.com/clip.mp4`)

    expect(response.status).toBe(502)
    expect(await response.text()).not.toContain('Connection diagnostic')
    expect(errors).toHaveBeenCalledExactlyOnceWith(expect.stringContaining('GET /media'), cause)
  })

  it.each([404, 503])(
    'retains upstream HTTP %s while diagnosing only server failures',
    async (status) => {
      const errors = vi.spyOn(console, 'error').mockImplementation(() => {})
      vi.stubGlobal('fetch', async () => new Response(null, { status }))

      const response = await httpFetch(`${origin}/media?url=https://fscgc.scgchc.com/clip.mp4`)

      expect(response.status).toBe(status)
      if (status === 503) {
        expect(errors).toHaveBeenCalledExactlyOnceWith(
          expect.stringContaining('GET /media'),
          expect.any(Error),
        )
      } else {
        expect(errors).not.toHaveBeenCalled()
      }
    },
  )

  it('diagnoses an upstream stream failure after headers have already been sent', async () => {
    const cause = new Error('Upstream stream interrupted')
    const errors = vi.spyOn(console, 'error').mockImplementation(() => {})
    let fail!: () => void
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('first'))
        fail = () => controller.error(cause)
      },
    })
    vi.stubGlobal('fetch', async () => new Response(body))
    const response = await httpFetch(`${origin}/media?url=https://fscgc.scgchc.com/clip.mp4`)
    const reader = response.body!.getReader()
    await reader.read()

    fail()

    await expect(reader.read()).rejects.toThrow()
    expect(errors).toHaveBeenCalledExactlyOnceWith(expect.stringContaining('GET /media'), cause)
  })

  it.each([
    '/app/v1/programs',
    '/app/v1/programs/1/dates/list',
    '/app/v1/programs/1/dates/2/contents/list',
  ])(
    'uses the Android guest profile for %s without forwarding browser credentials',
    async (path) => {
      const upstream = vi.fn().mockResolvedValue(new Response('{"rs":200,"data":[]}'))
      vi.stubGlobal('fetch', upstream)
      const response = await httpFetch(`${origin}/api${path}`, {
        headers: {
          Cookie: 'other=private; sctv-dl-device-id=dd6694f8-a985-4dd5-8425-d7c6d811793d',
          Authorization: 'Bearer browser-secret',
          userId: 'browser-user',
          deviceModel: 'browser-model',
        },
      })

      expect(response.status).toBe(200)
      const options = upstream.mock.calls[0]![1] as RequestInit
      const headers = new Headers(options.headers)
      expect(Object.fromEntries(headers)).toEqual({
        accept: 'application/json',
        'accept-encoding': 'gzip',
        appversion: '9.6.1.5',
        authorization: '',
        captchaid: '',
        devicebrand: 'google',
        deviceid: 'dd6694f8-a985-4dd5-8425-d7c6d811793d',
        devicemodel: 'Pixel 8',
        devicetype: 'android',
        systemversion: '14',
        'user-agent': 'okhttp/4.12.0',
        userid: '',
      })
      expect(options.body).toBeUndefined()
      expect(response.headers.has('set-cookie')).toBe(false)
    },
  )

  it('persists a generated device identity across programme requests with a local cookie', async () => {
    const upstream = vi.fn().mockImplementation(() => Promise.resolve(new Response('{}')))
    vi.stubGlobal('fetch', upstream)
    const first = await httpFetch(`${origin}/api/app/v1/programs`)
    const cookie = first.headers.get('set-cookie')!
    const firstHeaders = new Headers(upstream.mock.calls[0]![1].headers)
    const deviceId = firstHeaders.get('deviceId')

    expect(deviceId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    )
    expect(cookie).toContain(`sctv-dl-device-id=${deviceId};`)
    expect(cookie).toContain('Path=/api;')
    expect(cookie).toContain('Max-Age=31536000;')
    expect(cookie).toContain('HttpOnly; SameSite=Lax')

    await httpFetch(`${origin}/api/app/v1/programs/1/dates/list`, {
      headers: { Cookie: cookie.split(';')[0]! },
    })

    const secondHeaders = new Headers(upstream.mock.calls[1]![1].headers)
    expect(secondHeaders.get('deviceId')).toBe(deviceId)
    expect(secondHeaders.has('cookie')).toBe(false)
  })

  it('replaces malformed local device cookies instead of forwarding arbitrary header values', async () => {
    const upstream = vi.fn().mockResolvedValue(new Response('{}'))
    vi.stubGlobal('fetch', upstream)
    const response = await httpFetch(`${origin}/api/app/v1/programs`, {
      headers: { Cookie: 'sctv-dl-device-id=invalid-device' },
    })

    expect(response.headers.get('set-cookie')).toContain('sctv-dl-device-id=')
    expect(new Headers(upstream.mock.calls[0]![1].headers).get('deviceId')).not.toBe(
      'invalid-device',
    )
  })

  it('returns media headers and an attachment filename for HEAD without a body', async () => {
    const upstream = vi.fn().mockResolvedValue(
      new Response(null, {
        headers: { 'Content-Type': 'video/mp4', 'Content-Length': '100' },
      }),
    )
    vi.stubGlobal('fetch', upstream)
    const query = new URLSearchParams({
      url: 'https://fscgc.scgchc.com/clip.mp4',
      download: '1',
      filename: '节目.mp4',
    })
    const response = await httpFetch(`${origin}/media?${query}`, {
      method: 'HEAD',
      headers: { Cookie: 'sctv-dl-device-id=dd6694f8-a985-4dd5-8425-d7c6d811793d' },
    })

    expect(response.status).toBe(200)
    expect(response.headers.get('content-length')).toBe('100')
    expect(response.headers.get('content-disposition')).toContain("filename*=UTF-8''")
    expect(await response.text()).toBe('')
    expect(response.headers.has('set-cookie')).toBe(false)
    expect(upstream.mock.calls[0]![1].headers).toEqual({
      Referer: 'https://scgc.video.play/',
      'Accept-Encoding': 'identity',
    })
    expect(upstream).toHaveBeenCalledWith(
      new URL('https://fscgc.scgchc.com/clip.mp4'),
      expect.objectContaining({ method: 'HEAD', redirect: 'manual' }),
    )
  })

  it('rejects unsupported methods before contacting upstream', async () => {
    const upstream = vi.fn()
    vi.stubGlobal('fetch', upstream)
    const response = await httpFetch(`${origin}/media`, { method: 'POST' })

    expect(response.status).toBe(405)
    expect(response.headers.get('allow')).toBe('GET, HEAD')
    expect(upstream).not.toHaveBeenCalled()
  })

  it('does not follow redirects from an allowlisted target', async () => {
    const cancel = vi.fn()
    const body = new ReadableStream({ cancel })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(body, {
          status: 302,
          headers: { Location: 'https://example.com/clip.mp4' },
        }),
      ),
    )
    const response = await httpFetch(`${origin}/media?url=https://fscgc.scgchc.com/clip.mp4`)

    expect(response.status).toBe(502)
    expect(response.headers.has('location')).toBe(false)
    expect(cancel).toHaveBeenCalledOnce()
  })

  it('omits an encoded content length when fetch supplies a decompressed body', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response('decompressed', {
          headers: { 'Content-Encoding': 'gzip', 'Content-Length': '3' },
        }),
      ),
    )
    const response = await httpFetch(`${origin}/api/app/v1/programs`)

    expect(response.headers.has('content-length')).toBe(false)
    expect(response.headers.has('content-encoding')).toBe(false)
    expect(await response.text()).toBe('decompressed')
  })

  it('aborts an upstream request when the downstream client disconnects', async () => {
    const errors = vi.spyOn(console, 'error').mockImplementation(() => {})
    let upstreamSignal: AbortSignal | undefined
    vi.stubGlobal('fetch', (_target: URL, options: RequestInit) => {
      upstreamSignal = options.signal as AbortSignal

      return new Promise<Response>((_resolve, reject) => {
        upstreamSignal!.addEventListener('abort', () => reject(new Error('Aborted')), {
          once: true,
        })
      })
    })
    const controller = new AbortController()
    const response = httpFetch(`${origin}/api/app/v1/programs`, {
      signal: controller.signal,
    }).catch(() => null)
    await vi.waitFor(() => expect(upstreamSignal).toBeDefined())
    controller.abort()
    await response
    await vi.waitFor(() => expect(upstreamSignal!.aborted).toBe(true))
    expect(errors).not.toHaveBeenCalled()
  })
})
