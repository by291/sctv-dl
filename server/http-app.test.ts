import { createServer } from 'node:http'
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { once } from 'node:events'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createHttpApp } from './http-app.ts'

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
