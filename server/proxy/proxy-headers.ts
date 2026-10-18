import { contentDisposition } from './proxy-policy.ts'
import { programmeHeaders } from './programme-headers.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ProxyTarget } from './proxy-policy.ts'

export function proxyRequestHeaders(
  request: IncomingMessage,
  response: ServerResponse,
  target: ProxyTarget,
): Record<string, string> {
  if (target.kind === 'programme-api') {
    return programmeHeaders(request, response)
  }

  const headers: Record<string, string> = {
    Referer: 'https://scgc.video.play/',
    'Accept-Encoding': 'identity',
  }
  if (request.headers.range) {
    headers.Range = request.headers.range
  }

  if (typeof request.headers['if-range'] === 'string') {
    headers['If-Range'] = request.headers['if-range']
  }

  return headers
}

export function proxyResponseHeaders(
  upstream: Response,
  target: ProxyTarget,
): Record<string, string> {
  const headers: Record<string, string> = {
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  }

  for (const name of [
    'content-type',
    'content-length',
    'content-range',
    'accept-ranges',
    'etag',
    'last-modified',
  ]) {
    // fetch decompresses encoded bodies, so their original length is no longer valid.
    if (name === 'content-length' && upstream.headers.has('content-encoding')) {
      continue
    }

    const value = upstream.headers.get(name)
    if (value) {
      headers[name] = value
    }
  }

  if (target.kind === 'media' && target.filename !== null) {
    headers['Content-Disposition'] = contentDisposition(target.filename)
  }

  return headers
}
