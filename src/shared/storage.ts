import { useStorage } from '@vueuse/core'
import { ref } from 'vue'

import type { z } from 'zod'

export function usePersistentState<T>(
  key: string,
  defaults: T,
  schema: z.ZodType<T>,
  options: { syncTabs?: boolean } = {},
) {
  const persisted = ref(true)
  let storage: Storage | undefined

  try {
    storage = localStorage
  } catch {
    persisted.value = false
  }

  const value = useStorage<T>(key, () => structuredClone(defaults), storage, {
    writeDefaults: false,
    listenToStorageChanges: options.syncTabs ?? true,
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
      write: (data) => JSON.stringify(data),
    },
  })

  return { value, persisted }
}
