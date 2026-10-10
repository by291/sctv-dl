import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { programmeProxy } from './server/vite-plugin.ts'

export default defineConfig({
  plugins: [vue(), programmeProxy()],
  optimizeDeps: { entries: ['index.html'] },
  server: { port: 5180, strictPort: true, watch: { ignored: ['**/android/**'] } },
  preview: { port: 4173, strictPort: true },
})
