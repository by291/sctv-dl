import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'node:url'
import { upstreamProxyPlugin } from './tooling/upstream-proxy-plugin.ts'
import packageMetadata from './package.json' with { type: 'json' }

export default defineConfig({
  define: { 'import.meta.env.APP_VERSION': JSON.stringify(packageMetadata.version) },
  clearScreen: false,
  build: process.env.TAURI_ENV_PLATFORM
    ? { target: process.env.TAURI_ENV_PLATFORM === 'windows' ? 'chrome105' : 'safari16' }
    : {},
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@shared': fileURLToPath(new URL('./shared', import.meta.url)),
    },
  },
  plugins: [vue(), upstreamProxyPlugin()],
  optimizeDeps: { entries: ['index.html'] },
  server: {
    port: 5180,
    strictPort: true,
    watch: { ignored: ['**/android/**', '**/src-tauri/**', '**/flutter/**', '**/apple/**'] },
  },
  preview: { port: 4173, strictPort: true },
})
