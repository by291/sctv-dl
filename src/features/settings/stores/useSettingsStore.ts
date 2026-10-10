import { defineStore } from 'pinia'
import { computed } from 'vue'

import { usePersistentState } from '@/shared/composables/usePersistentState'
import { settingsSchema } from '@/features/settings/model/settings-schema'

import type { Settings } from '@/features/settings/model/settings-schema'

export const useSettingsStore = defineStore('settings', () => {
  const { value, persisted } = usePersistentState(
    'sctv-dl:settings',
    settingsSchema.parse({}),
    settingsSchema,
  )

  // Storage events replace the object; computed refs keep pointing to the latest version.
  function preference<K extends keyof Settings>(key: K) {
    return computed({
      get: () => value.value[key],
      set: (next: Settings[K]) => {
        value.value[key] = next
      },
    })
  }

  const quality = preference('quality')
  const theme = preference('theme')
  const favourites = preference('favourites')

  function toggleFavourite(id: string) {
    favourites.value = favourites.value.includes(id)
      ? favourites.value.filter((value) => value !== id)
      : [...favourites.value, id]
  }

  return { quality, theme, favourites, persisted, toggleFavourite }
})
