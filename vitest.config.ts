import { configDefaults, defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'node:url'
import packageMetadata from './package.json' with { type: 'json' }

export default defineConfig({
  define: { 'import.meta.env.APP_VERSION': JSON.stringify(packageMetadata.version) },
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src/', import.meta.url)),
      '@shared': fileURLToPath(new URL('./shared/', import.meta.url)),
    },
  },
  test: { environment: 'node', exclude: [...configDefaults.exclude, 'apple/**'] },
})
