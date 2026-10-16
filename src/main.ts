import '@/styles/global.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from '@/App.vue'
import { createAppRouter } from '@/router'
import { createPlatform } from '@/platform/create-platform'
import { startWithRecovery } from '@/platform/startup'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import { platformKey } from '@/shared/platform/usePlatform'

const root = document.querySelector<HTMLElement>('#app')!

void startWithRecovery(root, async () => {
  const platform = await createPlatform()
  const router = createAppRouter(platform.kind)
  const pinia = createPinia()
  const settings = useSettingsStore(pinia)
  let stopExit: (() => void) | undefined

  try {
    stopExit = await platform.prepareExit?.(async () => {
      await settings.flush()

      return settings.persisted
    })

    await settings.hydrate(platform.settings)
    const app = createApp(App).provide(platformKey, platform).use(pinia).use(router)

    app.onUnmount(() => {
      stopExit?.()
      settings.$dispose()
      void platform.dispose()
    })

    app.mount(root)
  } catch (error) {
    stopExit?.()
    settings.$dispose()
    await platform.dispose()

    throw error
  }
})
