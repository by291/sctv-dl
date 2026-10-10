import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'node:url'
import { upstreamProxyPlugin } from './tooling/upstream-proxy-plugin.ts'

export default defineConfig({
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  plugins: [vue(), upstreamProxyPlugin()],
  optimizeDeps: { entries: ['index.html'] },
  server: { port: 5180, strictPort: true, watch: { ignored: ['**/android/**'] } },
  preview: { port: 4173, strictPort: true },
})
