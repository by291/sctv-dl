import { useColorMode } from '@vueuse/core'
import { computed, watchEffect } from 'vue'

import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'

export function useAppTheme() {
  const settings = useSettingsStore()
  const preference = computed<'light' | 'dark' | 'auto'>({
    get: () => (settings.theme === 'system' ? 'auto' : settings.theme),
    set: (value) => {
      settings.theme = value === 'auto' ? 'system' : value
    },
  })

  // Reuse settings storage instead of adding a second theme key and listener.
  const mode = useColorMode({ attribute: 'data-theme', storageRef: preference })
  const isDark = computed(() => mode.value === 'dark')

  // Keep mobile browser chrome in step with the saved theme.
  watchEffect(() => {
    const background =
      getComputedStyle(document.documentElement).getPropertyValue('--bg').trim() ||
      (isDark.value ? '#111613' : '#f2f4ee')
    document
      .querySelector<HTMLMetaElement>('meta[name="theme-color"]')
      ?.setAttribute('content', background)
  })

  return { isDark }
}
