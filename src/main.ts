import '@/styles/global.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from '@/App.vue'
import { router } from '@/router'
import { createWebPlatform } from '@/platform/web-platform'
import { platformKey } from '@/shared/platform/usePlatform'

const platform = createWebPlatform()
const app = createApp(App).provide(platformKey, platform).use(createPinia()).use(router)
app.onUnmount(() => {
  void platform.dispose()
})
app.mount('#app')
