import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'

import { contentDisposition, validateMediaTarget } from './media.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'

async function serve(request: IncomingMessage, response: ServerResponse, local: URL) {
  if (!['GET', 'HEAD'].includes(request.method || '')) {
    response.writeHead(405, { Allow: 'GET, HEAD' }).end()

    return
  }

  const media = local.pathname === '/media'
  let target: URL
  try {
    if (media) {
      target = validateMediaTarget(local.searchParams.get('url') || '')
    } else {
      const path = local.pathname.slice('/api'.length)
      if (!/^\/app\/v1\/programs(?:\/\d+\/dates(?:\/list|\/\d+\/contents\/list))?$/.test(path)) {
        throw new Error('不支持的节目接口')
      }

      target = new URL(path, 'https://gw.scgchc.com')
      if (path === '/app/v1/programs') {
        target.search = '?page=0&size=100'
      }
    }
  } catch {
    response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' }).end('不支持的代理地址')

    return
  }

  const controller = new AbortController()
  const abort = () => controller.abort()
  request.once('aborted', abort)
  response.once('close', abort)
  const timer = setTimeout(abort, 20_000)
  try {
    const headers: Record<string, string> = media
      ? { Referer: 'https://scgc.video.play/' }
      : { Accept: 'application/json' }
    headers['Accept-Encoding'] = 'identity'
    if (media && request.headers.range) {
      headers.Range = request.headers.range
    }

    if (media && typeof request.headers['if-range'] === 'string') {
      headers['If-Range'] = request.headers['if-range']
    }

    const upstream = await fetch(target, {
      method: request.method,
      headers,
      redirect: 'manual',
      signal: controller.signal,
    })
    clearTimeout(timer)
    if (upstream.status >= 300 && upstream.status < 400) {
      await upstream.body?.cancel()
      throw new Error('视频服务返回不支持的重定向')
    }

    if (!upstream.ok) {
      await upstream.body?.cancel()
      response
        .writeHead(upstream.status, { 'Content-Type': 'text/plain; charset=utf-8' })
        .end(`上游服务错误：${upstream.status}`)

      return
    }

    const copied: Record<string, string> = {
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    }
    for (const key of [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
      'etag',
      'last-modified',
    ]) {
      const value = upstream.headers.get(key)
      // fetch decompresses encoded bodies, so their original length is no longer valid.
      if (key === 'content-length' && upstream.headers.has('content-encoding')) {
        continue
      }

      if (value) {
        copied[key] = value
      }
    }

    if (media && local.searchParams.get('download') === '1') {
      copied['Content-Disposition'] = contentDisposition(
        local.searchParams.get('filename') || 'programme.mp4',
      )
    }

    response.writeHead(upstream.status, copied)
    if (request.method === 'HEAD' || !upstream.body) {
      response.end()

      return
    }

    await pipeline(
      Readable.fromWeb(upstream.body as Parameters<typeof Readable.fromWeb>[0]),
      response,
    )
  } catch {
    if (response.destroyed) {
      return
    }

    if (response.headersSent) {
      response.destroy()
    } else {
      response
        .writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' })
        .end('无法连接节目服务，请稍后重试')
    }
  } finally {
    clearTimeout(timer)
    request.off('aborted', abort)
    response.off('close', abort)
  }
}

export function programmeProxyMiddleware(
  request: IncomingMessage,
  response: ServerResponse,
  next: () => void,
): void {
  let url: URL
  try {
    url = new URL(request.url || '/', 'http://localhost')
  } catch {
    response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Invalid URL')

    return
  }

  if (url.pathname === '/media' || url.pathname === '/api' || url.pathname.startsWith('/api/')) {
    void serve(request, response, url)
  } else {
    next()
  }
}
