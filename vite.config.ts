import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { programmeProxy } from './server/proxy.ts'

export default defineConfig({
  plugins: [vue(), tailwindcss(), programmeProxy()],
  experimental: { bundledDev: true },
  server: { port: 5180, strictPort: true },
  preview: { port: 4173, strictPort: true },
})
