import { useStorage } from '@vueuse/core'
import { ref } from 'vue'

import type { z } from 'zod'

// Load validated settings and expose whether browser persistence is available.
export function usePersistentState<T>({
  key,
  defaults,
  schema,
  shouldSyncTabs = true,
}: {
  key: string
  defaults: T
  schema: z.ZodType<T>
  shouldSyncTabs?: boolean
}) {
  const persisted = ref(true)
  let storage: Storage | undefined

  try {
    storage = localStorage
  } catch {
    persisted.value = false
  }

  const value = useStorage<T>(key, () => structuredClone(defaults), storage, {
    writeDefaults: false,
    listenToStorageChanges: shouldSyncTabs,
    onError: () => {
      persisted.value = false
    },
    serializer: {
      read(raw) {
        try {
          const result = schema.safeParse(JSON.parse(raw))

          return result.success ? result.data : structuredClone(defaults)
        } catch {
          return structuredClone(defaults)
        }
      },
      write: (value) => JSON.stringify(value),
    },
  })

  return { value, persisted }
}
