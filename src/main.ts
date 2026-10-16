import '@/styles/global.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from '@/App.vue'
import { router } from '@/router'
import { createWebPlatform } from '@/platform/web-platform'
import { startWithRecovery } from '@/platform/startup'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import { platformKey } from '@/shared/platform/usePlatform'

const root = document.querySelector<HTMLElement>('#app')!
void startWithRecovery(root, async () => {
  const platform = createWebPlatform()
  const pinia = createPinia()
  const settings = useSettingsStore(pinia)
  try {
    await settings.hydrate(platform.settings)
    const app = createApp(App).provide(platformKey, platform).use(pinia).use(router)
    app.onUnmount(() => {
      settings.$dispose()
      void platform.dispose()
    })
    app.mount(root)
  } catch (error) {
    settings.$dispose()
    await platform.dispose()
    throw error
  }
})
