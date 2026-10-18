import { defineStore } from 'pinia'
import { onScopeDispose, ref } from 'vue'

import { errorMessage } from '@/shared/utils/errors'

import type { HistoryEntry, HistorySnapshot } from '@shared/contracts/history'
import type { ContentRef } from '@shared/contracts/programmes'
import type { HistoryPort } from '@/shared/platform/ports'

export const useHistoryStore = defineStore('history', () => {
  const entries = ref<HistoryEntry[]>([])
  const loading = ref(false)
  const error = ref('')
  const persisted = ref(true)
  const warning = ref<string | null>(null)
  const captures = new Set<() => Promise<void>>()
  let port: HistoryPort | undefined
  let unsubscribe: (() => void) | undefined
  let connectionVersion = 0
  let snapshotRevision = -1

  function apply(snapshot: HistorySnapshot): void {
    if (snapshot.revision < snapshotRevision) {
      return
    }

    snapshotRevision = snapshot.revision
    entries.value = snapshot.entries
    persisted.value = snapshot.persisted
    warning.value = snapshot.warning
  }

  function detach(): void {
    connectionVersion += 1
    unsubscribe?.()
    unsubscribe = undefined
    port = undefined
    loading.value = false
  }

  async function attach(next: HistoryPort): Promise<void> {
    if (port === next) {
      return
    }

    detach()
    port = next
    const version = connectionVersion

    snapshotRevision = -1
    loading.value = true
    error.value = ''

    try {
      // Subscribe before loading; an event may contain a newer revision than list().
      const stop = await next.subscribe((snapshot) => {
        if (version === connectionVersion) {
          apply(snapshot)
        }
      })
      if (version !== connectionVersion) {
        stop()

        return
      }

      unsubscribe = stop

      const snapshot = await next.list()

      if (version === connectionVersion) {
        apply(snapshot)
      }
    } catch (cause) {
      if (version === connectionVersion) {
        error.value = errorMessage(cause)
        unsubscribe?.()
        unsubscribe = undefined
      }
    } finally {
      if (version === connectionVersion) {
        loading.value = false
      }
    }
  }

  async function reload(): Promise<void> {
    const current = port
    if (!current) {
      return
    }

    // Reattach when a failed initial subscription left observation disconnected.
    if (!unsubscribe) {
      port = undefined
      await attach(current)

      return
    }

    const version = connectionVersion
    try {
      const snapshot = await current.list()
      if (version === connectionVersion) {
        apply(snapshot)
        error.value = ''
      }
    } catch (cause) {
      if (version === connectionVersion) {
        error.value = errorMessage(cause)
      }
    }
  }

  async function action(run: (current: HistoryPort) => Promise<void>): Promise<void> {
    const current = port
    const version = connectionVersion
    if (!current) {
      error.value = '观看历史尚未连接，请重试'

      return
    }

    error.value = ''
    try {
      await run(current)
      if (version === connectionVersion) {
        await reload()
      }
    } catch (cause) {
      if (version === connectionVersion) {
        error.value = errorMessage(cause)
      }
    }
  }

  function registerCapture(capture: () => Promise<void>): () => void {
    captures.add(capture)

    return () => {
      captures.delete(capture)
    }
  }

  async function captureActive(): Promise<void> {
    await Promise.all([...captures].map((capture) => capture()))
  }

  onScopeDispose(() => {
    detach()
    captures.clear()
  })

  return {
    entries,
    loading,
    error,
    persisted,
    warning,
    attach,
    detach,
    remove: (content: ContentRef) => action((current) => current.remove(content)),
    clear: () => action((current) => current.clear()),
    reload,
    registerCapture,
    captureActive,
  }
})
