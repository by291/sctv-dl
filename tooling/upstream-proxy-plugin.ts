import { proxyMiddleware } from '../server/proxy/proxy-middleware.ts'

import type { Plugin } from 'vite'

export function upstreamProxyPlugin(): Plugin {
  return {
    name: 'sctv-programme-proxy',
    configureServer(server) {
      server.middlewares.use(proxyMiddleware)
    },
    configurePreviewServer(server) {
      server.middlewares.use(proxyMiddleware)
    },
  }
}
