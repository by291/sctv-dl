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

  // A replacement connection invalidates every pending load, subscription, and queued save.
  let connectionVersion = 0

  // External snapshots advance the shared revision; only user edits advance the local revision.
  let snapshotRevision = 0
  let localEditRevision = 0
  let applyingSnapshot = false

  let pendingSaveCount = 0
  let saveQueue = Promise.resolve()

  function snapshot(): Settings {
    return structuredClone(toRaw(value.value))
  }

  function queueSave(current: SettingsPort, next: Settings): void {
    const version = connectionVersion
    pendingSaveCount += 1

    saveQueue = saveQueue.then(async () => {
      try {
        if (version !== connectionVersion) {
          return
        }

        await current.save(next)

        if (version === connectionVersion) {
          persisted.value = true
        }
      } catch {
        if (version === connectionVersion) {
          persisted.value = false
        }
      } finally {
        pendingSaveCount -= 1
      }
    })
  }

  watch(
    value,
    () => {
      if (applyingSnapshot) {
        return
      }

      snapshotRevision += 1
      localEditRevision += 1

      if (port) {
        queueSave(port, snapshot())
      }
    },
    { deep: true, flush: 'sync' },
  )

  function applySnapshot(next: Settings): void {
    const parsed = settingsSchema.parse(next)
    applyingSnapshot = true

    try {
      value.value = parsed
    } finally {
      applyingSnapshot = false
    }
  }

  async function hydrate(next: SettingsPort): Promise<void> {
    unsubscribe?.()
    unsubscribe = undefined
    connectionVersion += 1
    const version = connectionVersion
    const initialSnapshotRevision = snapshotRevision
    const initialLocalEditRevision = localEditRevision
    port = undefined

    try {
      // Subscribe first so changes during the initial load cannot be lost to its older snapshot.
      const dispose = await next.subscribe((incoming) => {
        // Save notifications must not replace edits that are still waiting in our queue.
        if (
          version === connectionVersion &&
          pendingSaveCount === 0 &&
          (port || localEditRevision === initialLocalEditRevision)
        ) {
          snapshotRevision += 1
          applySnapshot(incoming)
        }
      })

      if (version !== connectionVersion) {
        dispose()

        return
      }

      unsubscribe = dispose
      const loaded = await next.load()

      if (version !== connectionVersion) {
        return
      }

      persisted.value = loaded.persisted

      if (snapshotRevision === initialSnapshotRevision) {
        applySnapshot(loaded.value)
      }

      port = next

      if (localEditRevision !== initialLocalEditRevision) {
        queueSave(next, snapshot())
      }
    } catch {
      if (version === connectionVersion) {
        persisted.value = false
        port = next
      }
    }
  }

  async function flush(): Promise<void> {
    // Edits made during a save append work, so await the queue until its tail stops changing.
    let saving: Promise<void>

    do {
      saving = saveQueue
      await saving
    } while (saving !== saveQueue)
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

  function toggleFavourite(id: string): void {
    favourites.value = favourites.value.includes(id)
      ? favourites.value.filter((value) => value !== id)
      : [...favourites.value, id]
  }

  onScopeDispose(() => {
    connectionVersion += 1
    unsubscribe?.()
    port = undefined
  })

  return {
    quality,
    theme,
    favourites,
    persisted,
    toggleFavourite,
    hydrate,
    flush,
    getWriteRevision: () => localEditRevision,
  }
})
