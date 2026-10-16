import { defineStore } from 'pinia'
import { computed, onScopeDispose, ref, toRaw, watch } from 'vue'

import { settingsSchema } from '@/features/settings/model/settings-schema'

import type { Settings } from '@/features/settings/model/settings-schema'
import type { SettingsPort } from '@/shared/platform/ports'

export const useSettingsStore = defineStore('settings', () => {
  const value = ref(settingsSchema.parse({}))
  const persisted = ref(true)

  let port: SettingsPort | undefined
  let unsubscribe: (() => void) | undefined
  let generation = 0
  let revision = 0
  let localRevision = 0
  let unsaved = 0
  let applying = false
  let pending = Promise.resolve()

  function snapshot(): Settings {
    return structuredClone(toRaw(value.value))
  }

  function save(current: SettingsPort, next: Settings) {
    const currentGeneration = generation
    unsaved += 1
    pending = pending.then(async () => {
      try {
        if (currentGeneration !== generation) {
          return
        }

        await current.save(next)
        if (currentGeneration === generation) {
          persisted.value = true
        }
      } catch {
        if (currentGeneration === generation) {
          persisted.value = false
        }
      } finally {
        unsaved -= 1
      }
    })
  }

  watch(
    value,
    () => {
      if (applying) {
        return
      }

      revision += 1
      localRevision += 1
      if (port) {
        save(port, snapshot())
      }
    },
    { deep: true, flush: 'sync' },
  )

  function apply(next: Settings) {
    applying = true
    value.value = settingsSchema.parse(next)
    applying = false
  }

  async function hydrate(next: SettingsPort): Promise<void> {
    unsubscribe?.()
    unsubscribe = undefined
    generation += 1
    const currentGeneration = generation
    const initialRevision = revision
    const initialLocalRevision = localRevision
    port = undefined
    try {
      const dispose = await next.subscribe((incoming) => {
        if (
          currentGeneration === generation &&
          !unsaved &&
          (port || localRevision === initialLocalRevision)
        ) {
          revision += 1
          apply(incoming)
        }
      })
      if (currentGeneration !== generation) {
        dispose()

        return
      }

      unsubscribe = dispose
      const loaded = await next.load()
      if (currentGeneration !== generation) {
        return
      }

      persisted.value = loaded.persisted
      if (revision === initialRevision) {
        apply(loaded.value)
      }

      port = next
      if (localRevision !== initialLocalRevision) {
        save(next, snapshot())
      }
    } catch {
      if (currentGeneration === generation) {
        persisted.value = false
        port = next
      }
    }
  }

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

  onScopeDispose(() => {
    generation += 1
    unsubscribe?.()
    port = undefined
  })

  return { quality, theme, favourites, persisted, toggleFavourite, hydrate, flush: () => pending }
})
