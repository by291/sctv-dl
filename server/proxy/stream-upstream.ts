import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'

import { reportHttpFailure } from '../http-diagnostics.ts'
import { proxyRequestHeaders, proxyResponseHeaders } from './proxy-headers.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ProxyTarget } from './proxy-policy.ts'

export async function streamUpstream(
  request: IncomingMessage,
  response: ServerResponse,
  target: ProxyTarget,
): Promise<void> {
  const diagnosticPath = target.kind === 'media' ? '/media' : '/api'
  const controller = new AbortController()
  const abort = () => controller.abort()
  request.once('aborted', abort)
  response.once('close', abort)

  // Only response headers have a deadline; downstream disconnect owns the whole transfer.
  const headerDeadline = setTimeout(abort, 20_000)

  try {
    const upstream = await fetch(target.url, {
      method: request.method,
      headers: proxyRequestHeaders(request, response, target),
      redirect: 'manual',
      signal: controller.signal,
    })
    clearTimeout(headerDeadline)

    if (upstream.status >= 300 && upstream.status < 400) {
      await upstream.body?.cancel()
      throw new Error('视频服务返回不支持的重定向')
    }

    if (!upstream.ok) {
      await upstream.body?.cancel()
      if (upstream.status >= 500) {
        reportHttpFailure(
          request.method,
          diagnosticPath,
          new Error(`Upstream returned HTTP ${upstream.status}`),
        )
      }

      response
        .writeHead(upstream.status, { 'Content-Type': 'text/plain; charset=utf-8' })
        .end(`上游服务错误：${upstream.status}`)

      return
    }

    response.writeHead(upstream.status, proxyResponseHeaders(upstream, target))

    if (request.method === 'HEAD' || !upstream.body) {
      response.end()

      return
    }

    const source = Readable.fromWeb(upstream.body as Parameters<typeof Readable.fromWeb>[0])
    source.once('error', (cause) => {
      // pipeline destroys the response on source errors, so capture them before close aborts it.
      if (!controller.signal.aborted) {
        reportHttpFailure(request.method, diagnosticPath, cause)
      }
    })

    await pipeline(source, response)
  } catch (cause) {
    if (response.destroyed) {
      return
    }

    reportHttpFailure(request.method, diagnosticPath, cause)

    if (response.headersSent) {
      response.destroy()
    } else {
      response
        .writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' })
        .end('无法连接节目服务，请稍后重试')
    }
  } finally {
    clearTimeout(headerDeadline)
    request.off('aborted', abort)
    response.off('close', abort)
  }
}
