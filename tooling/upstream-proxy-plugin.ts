import { proxyMiddleware } from '../server/proxy/proxy-middleware.ts'
import { clientApiMiddleware } from '../server/client-api/client-api-middleware.ts'
import { validateClientApiEnvironment } from './client-api-config.ts'

import type { Plugin } from 'vite'

export function upstreamProxyPlugin(): Plugin {
  return {
    name: 'sctv-programme-proxy',
    configResolved(config) {
      validateClientApiEnvironment(config.env.VITE_API_BASE, config.env.VITE_CLIENT_API_BASE)
    },
    configureServer(server) {
      server.middlewares.use(clientApiMiddleware)
      server.middlewares.use(proxyMiddleware)
    },
    configurePreviewServer(server) {
      server.middlewares.use(clientApiMiddleware)
      server.middlewares.use(proxyMiddleware)
    },
  }
}
