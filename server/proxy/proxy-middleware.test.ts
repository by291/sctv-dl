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
  server.closeAllConnections()
  await new Promise<void>((resolve) => server.close(() => resolve()))
})

describe('proxy transport contracts', () => {
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
    const response = await httpFetch(`${origin}/media?${query}`, { method: 'HEAD' })

    expect(response.status).toBe(200)
    expect(response.headers.get('content-length')).toBe('100')
    expect(response.headers.get('content-disposition')).toContain("filename*=UTF-8''")
    expect(await response.text()).toBe('')
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
  })
})
