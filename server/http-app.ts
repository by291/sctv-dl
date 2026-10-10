import { statSync } from 'node:fs'
import { join } from 'node:path'
import sirv from 'sirv'

import { proxyMiddleware } from './proxy/proxy-middleware.ts'

import type { RequestListener } from 'node:http'

export function createHttpApp(assetsDirectory: string): RequestListener {
  if (!statSync(join(assetsDirectory, 'index.html'), { throwIfNoEntry: false })?.isFile()) {
    throw new Error('Frontend build is missing. Run "pnpm build" before "pnpm start".')
  }

  const staticFiles = sirv(assetsDirectory, {
    single: true,
    etag: true,
    ignores: [/^\/(?:api|media|assets)(?:\/|$)/, /(?:^|\/)\./],
    setHeaders(response, pathname) {
      // Vite's built assets have content hashes; the HTML must revalidate on every visit.
      response.setHeader(
        'Cache-Control',
        pathname.startsWith('/assets/') ? 'public, max-age=31536000, immutable' : 'no-cache',
      )
    },
  })

  return (request, response) => {
    response.setHeader('X-Content-Type-Options', 'nosniff')
    if (!['GET', 'HEAD'].includes(request.method || '')) {
      response.writeHead(405, { Allow: 'GET, HEAD' }).end()

      return
    }

    proxyMiddleware(request, response, () => {
      if (new URL(request.url || '/', 'http://localhost').pathname === '/healthz') {
        response.writeHead(200, {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-store',
        })
        response.end(request.method === 'HEAD' ? undefined : '{"status":"ok"}')

        return
      }

      // Frontend assets use full responses; Range support belongs to the media route.
      delete request.headers.range
      staticFiles(request, response, () => {
        response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found')
      })
    })
  }
}
