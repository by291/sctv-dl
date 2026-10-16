import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'

import { contentDisposition } from './proxy-policy.ts'
import { programmeHeaders } from './programme-headers.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ProxyTarget } from './proxy-policy.ts'

export async function streamUpstream(
  request: IncomingMessage,
  response: ServerResponse,
  target: ProxyTarget,
): Promise<void> {
  const media = target.kind === 'media'
  const controller = new AbortController()
  const abort = () => controller.abort()
  request.once('aborted', abort)
  response.once('close', abort)
  const timer = setTimeout(abort, 20_000)
  try {
    const headers: Record<string, string> = media
      ? { Referer: 'https://scgc.video.play/', 'Accept-Encoding': 'identity' }
      : programmeHeaders(request, response)
    if (media && request.headers.range) {
      headers.Range = request.headers.range
    }

    if (media && typeof request.headers['if-range'] === 'string') {
      headers['If-Range'] = request.headers['if-range']
    }

    const upstream = await fetch(target.url, {
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

    if (target.kind === 'media' && target.filename !== null) {
      copied['Content-Disposition'] = contentDisposition(target.filename)
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
