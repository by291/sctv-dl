import { onMounted, onScopeDispose, ref } from 'vue'

import { errorMessage } from '@/shared/utils/errors'

import type { Ref } from 'vue'
import type { AppPlatform } from '@/shared/platform/ports'

interface DownloadDirectoryWorkflow {
  directory: Ref<string | null>
  error: Ref<string>
  busy: Ref<boolean>
  canChooseDirectory: boolean
  chooseDirectory(): Promise<void>
}

export function useDownloadDirectory(
  downloads: AppPlatform['downloads'],
): DownloadDirectoryWorkflow {
  const nativeDownloads = downloads.kind === 'native' ? downloads : undefined

  const directory = ref<string | null>(null)
  const error = ref('')
  const busy = ref(false)
  let disposed = false
  let revision = 0

  function isCurrent(current: number): boolean {
    return !disposed && current === revision
  }

  async function loadDirectory(): Promise<void> {
    if (!nativeDownloads) {
      return
    }

    const current = ++revision

    try {
      const path = await nativeDownloads.getDirectory()

      if (isCurrent(current)) {
        directory.value = path
        error.value = ''
      }
    } catch (cause) {
      if (isCurrent(current)) {
        error.value = errorMessage(cause)
      }
    }
  }

  async function chooseDirectory(): Promise<void> {
    if (!nativeDownloads || busy.value) {
      return
    }

    busy.value = true
    const current = ++revision

    try {
      const path = await nativeDownloads.chooseDirectory()

      if (isCurrent(current) && path !== null) {
        directory.value = path
        error.value = ''
      } else if (isCurrent(current)) {
        // Re-read persisted native state even when the user dismisses the picker.
        await loadDirectory()
      }
    } catch (cause) {
      if (isCurrent(current)) {
        error.value = errorMessage(cause)
      }
    } finally {
      if (!disposed) {
        busy.value = false
      }
    }
  }

  onMounted(() => {
    void loadDirectory()
  })

  onScopeDispose(() => {
    disposed = true
  })

  return { directory, error, busy, canChooseDirectory: !!nativeDownloads, chooseDirectory }
}
