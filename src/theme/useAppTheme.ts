import { useColorMode } from '@vueuse/core'
import { computed } from 'vue'

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

  return { isDark: computed(() => mode.value === 'dark') }
}
