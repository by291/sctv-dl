import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { programmeProxy } from './server/proxy.ts'

export default defineConfig({
  plugins: [vue(), programmeProxy()],
  server: { port: 5180, strictPort: true },
  preview: { port: 4173, strictPort: true },
})
