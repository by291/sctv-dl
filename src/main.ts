import '@/styles/global.css'

import { createApp } from 'vue'
import { createPinia, disposePinia } from 'pinia'

import App from '@/App.vue'
import { createAppRouter } from '@/router'
import { createPlatform } from '@/platform/create-platform'
import { startWithRecovery } from '@/platform/startup'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import { useHistoryStore } from '@/features/history/stores/useHistoryStore'
import { flushPersistence } from '@/platform/persistence-lifecycle'
import { platformKey } from '@/shared/platform/usePlatform'
import {
  createScrollRestoration,
  scrollRestorationKey,
} from '@/shared/navigation/scroll-restoration'

const root = document.querySelector<HTMLElement>('#app')!

void startWithRecovery(root, async () => {
  const platform = await createPlatform()
  const scrollRestoration = createScrollRestoration()
  const router = createAppRouter(platform.kind, scrollRestoration)
  const pinia = createPinia()
  const settings = useSettingsStore(pinia)
  const history = useHistoryStore(pinia)
  let stopExit: (() => void) | undefined
  let disposal: Promise<void> | undefined

  function disposeApplication(): Promise<void> {
    // Startup recovery and unmount share the same owner and may both request cleanup.
    disposal ??= (async () => {
      stopExit?.()
      scrollRestoration.cancel()
      disposePinia(pinia)
      await platform.dispose()
    })()

    return disposal
  }

  try {
    stopExit = await platform.prepareExit?.(async () => {
      await history.captureActive()

      return flushPersistence([
        {
          getWriteRevision: settings.getWriteRevision,
          flush: settings.flush,
          isPersisted: async () => settings.persisted,
        },
        {
          getWriteRevision: platform.history.getWriteRevision,
          flush: platform.history.flush,
          isPersisted: async () => (await platform.history.list()).persisted,
        },
      ])
    })

    await settings.hydrate(platform.settings)
    await history.attach(platform.history)
    const app = createApp(App)
      .provide(platformKey, platform)
      .provide(scrollRestorationKey, scrollRestoration)
      .use(pinia)
      .use(router)

    app.onUnmount(() => {
      void disposeApplication().catch((cause) => {
        console.error('Failed to release application resources', cause)
      })
    })

    app.mount(root)
  } catch (error) {
    await disposeApplication().catch((cause) => {
      // Keep the startup failure actionable even when teardown also fails.
      console.error('Failed to release application resources after startup failure', cause)
    })

    throw error
  }
})
