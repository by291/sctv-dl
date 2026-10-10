import { isProxyPath, resolveProxyTarget } from './proxy-policy.ts'
import { streamUpstream } from './stream-upstream.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ProxyTarget } from './proxy-policy.ts'

export function proxyMiddleware(
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

  if (!isProxyPath(url.pathname)) {
    next()

    return
  }

  if (!['GET', 'HEAD'].includes(request.method || '')) {
    response.writeHead(405, { Allow: 'GET, HEAD' }).end()

    return
  }

  let target: ProxyTarget
  try {
    target = resolveProxyTarget(url)
  } catch {
    response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' }).end('不支持的代理地址')

    return
  }

  void streamUpstream(request, response, target)
}
