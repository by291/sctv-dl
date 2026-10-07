import { programmeProxyMiddleware } from './proxy.ts'

import type { Plugin } from 'vite'

export function programmeProxy(): Plugin {
  return {
    name: 'sctv-programme-proxy',
    configureServer(server) {
      server.middlewares.use(programmeProxyMiddleware)
    },
    configurePreviewServer(server) {
      server.middlewares.use(programmeProxyMiddleware)
    },
  }
}
