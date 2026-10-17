import { computed, onScopeDispose, ref } from 'vue'
import { defineStore } from 'pinia'

import { errorMessage } from '@/shared/utils/errors'
import {
  availableDownloadActions,
  isActiveDownload,
} from '@/features/downloads/model/download-actions'

import type {
  DownloadRequest,
  DownloadStartResult,
  DownloadTask,
  FileFailure,
  DownloadEvent,
  DownloadSnapshot,
  DownloadActionRequest,
} from '@shared/contracts/downloads'
import type { NativeDownloadPort } from '@/shared/platform/ports'

export interface BatchResult {
  applied: number
  skipped: number
  failures: Array<{ taskId: string; message: string }>
}

export interface DownloadTarget {
  taskId: string
  attemptId: string
}

export const useDownloadTasksStore = defineStore('downloadTasks', () => {
  const tasks = ref<DownloadTask[]>([])
  const failures = ref<FileFailure[]>([])
  const error = ref('')
  const loading = ref(false)
  const pendingActions = ref<string[]>([])
  const batchResult = ref<BatchResult | null>(null)
  const activeCount = computed(() => tasks.value.filter(isActiveDownload).length)
  let port: NativeDownloadPort | undefined
  let dispose: (() => void) | undefined
  let generation = 0
  let epoch: string | null = null
  let snapshotRevision = -1
  const retiredEpochs = new Set<string>()
  const changes = new Map<string, number>()
  const removed = new Set<string>()

  function merge(task: DownloadTask): void {
    if (removed.has(task.id)) {
      return
    }

    const index = tasks.value.findIndex((value) => value.id === task.id)
    const previous = tasks.value[index]
    if (previous && previous.revision >= task.revision) {
      return
    }

    if (index < 0) {
      tasks.value.push(task)
    } else {
      tasks.value[index] = task
    }
  }

  function useEpoch(next: string): boolean {
    if (retiredEpochs.has(next)) {
      return false
    }

    if (epoch === next) {
      return true
    }

    if (epoch !== null) {
      retiredEpochs.add(epoch)
    }

    epoch = next
    tasks.value = []
    changes.clear()
    removed.clear()
    snapshotRevision = -1

    return true
  }

  function applySnapshot(snapshot: DownloadSnapshot): void {
    // A snapshot started before a process replacement cannot switch us back.
    if (epoch !== null && epoch !== snapshot.epoch) {
      return
    }

    if (!useEpoch(snapshot.epoch) || snapshot.revision < snapshotRevision) {
      return
    }

    const ids = new Set(snapshot.tasks.map((task) => task.id))
    tasks.value = tasks.value.filter(
      (task) => ids.has(task.id) || (changes.get(task.id) ?? -1) > snapshot.revision,
    )
    for (const task of snapshot.tasks) {
      if ((changes.get(task.id) ?? -1) <= snapshot.revision) {
        merge(task)
      }
    }

    snapshotRevision = snapshot.revision
  }

  function applyEvent(event: DownloadEvent): void {
    if (!useEpoch(event.epoch) || event.revision <= snapshotRevision) {
      return
    }

    const id = event.kind === 'upsert' ? event.task.id : event.taskId
    if ((changes.get(id) ?? -1) >= event.revision) {
      return
    }

    changes.set(id, event.revision)
    if (event.kind === 'remove') {
      removed.add(id)
      tasks.value = tasks.value.filter((task) => task.id !== id)
    } else {
      merge(event.task)
    }
  }

  function detach(): void {
    generation += 1
    dispose?.()
    dispose = undefined
    port = undefined
    loading.value = false
  }

  async function attach(next: NativeDownloadPort): Promise<void> {
    detach()
    port = next
    const current = generation
    loading.value = true
    error.value = ''
    // The new observer takes a complete snapshot; events from a detached observer
    // are ignored by its generation even if native unsubscribe completes later.
    epoch = null
    retiredEpochs.clear()
    changes.clear()
    removed.clear()
    snapshotRevision = -1
    try {
      const unsubscribe = await next.subscribeEvents((event) => {
        if (current !== generation) {
          return
        }

        const previous = epoch
        applyEvent(event)
        if (previous !== null && epoch !== previous) {
          void next
            .snapshot()
            .then((snapshot) => {
              if (current === generation) {
                applySnapshot(snapshot)
              }
            })
            .catch((cause) => {
              if (current === generation) {
                error.value = errorMessage(cause)
              }
            })
        }
      })
      if (current !== generation) {
        unsubscribe()

        return
      }

      dispose = unsubscribe
      const snapshot = await next.snapshot()
      if (current === generation) {
        applySnapshot(snapshot)
      }
    } catch (cause) {
      if (current === generation) {
        dispose?.()
        dispose = undefined
        error.value = errorMessage(cause)
      }
    } finally {
      if (current === generation) {
        loading.value = false
      }
    }
  }

  function recordStart(result: DownloadStartResult): void {
    if (result.kind !== 'native') {
      return
    }

    for (const failure of result.failures) {
      if (
        !failures.value.some(
          (previous) =>
            previous.contentId === failure.contentId && previous.message === failure.message,
        )
      ) {
        failures.value.push(failure)
      }
    }
  }

  async function start(
    request: DownloadRequest,
    source: NativeDownloadPort | undefined = port,
  ): Promise<DownloadStartResult> {
    if (!source) {
      throw new Error('桌面下载服务尚未连接')
    }

    const result = await source.start(request)
    recordStart(result)

    return result
  }

  async function runBatch(
    action: DownloadActionRequest['action'],
    targets: DownloadTarget[],
  ): Promise<BatchResult> {
    const result: BatchResult = { applied: 0, skipped: 0, failures: [] }
    const source = port
    const current = generation
    const captured = targets.map((target) => ({ ...target }))
    for (const target of captured) {
      const task = tasks.value.find((value) => value.id === target.taskId)
      if (
        !source ||
        generation !== current ||
        !task ||
        task.attemptId !== target.attemptId ||
        !availableDownloadActions(task).includes(action) ||
        pendingActions.value.includes(task.id)
      ) {
        result.skipped += 1
        continue
      }

      pendingActions.value.push(task.id)
      try {
        const response = await source.act({ ...target, action })
        if (response.kind === 'skipped') {
          result.skipped += 1
        } else {
          result.applied += 1
          if (current === generation) {
            if (response.task) {
              merge(response.task)
            } else if (action === 'remove') {
              removed.add(task.id)
              changes.set(task.id, Infinity)
              tasks.value = tasks.value.filter((value) => value.id !== task.id)
            }
          }
        }
      } catch (cause) {
        result.failures.push({ taskId: target.taskId, message: errorMessage(cause) })
      } finally {
        pendingActions.value = pendingActions.value.filter((id) => id !== target.taskId)
      }
    }

    if (generation === current) {
      batchResult.value = result
      error.value = result.failures[0]?.message ?? ''
    }

    return result
  }

  async function act(id: string, action: DownloadActionRequest['action']): Promise<BatchResult> {
    const task = tasks.value.find((value) => value.id === id)

    return runBatch(action, task ? [{ taskId: id, attemptId: task.attemptId }] : [])
  }

  onScopeDispose(detach)

  return {
    tasks,
    failures,
    error,
    loading,
    pendingActions,
    batchResult,
    activeCount,
    attach,
    detach,
    start,
    act,
    runBatch,
    cancel: (id: string) => act(id, 'cancel'),
    retry: (id: string) => act(id, 'restart'),
  }
})
