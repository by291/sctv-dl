import { computed, onScopeDispose, ref } from 'vue'
import { defineStore } from 'pinia'

import { errorMessage } from '@/shared/utils/errors'
import {
  createDownloadTaskState,
  resetDownloadObservation,
  applyDownloadSnapshot,
  applyDownloadEvent,
  applyDownloadCommandResult,
} from '@/features/downloads/model/download-task-state'
import {
  availableDownloadActions,
  isActiveDownload,
} from '@/features/downloads/model/download-actions'

import type {
  DownloadRequest,
  DownloadStartResult,
  FileFailure,
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
  const taskState = ref(createDownloadTaskState())
  const failures = ref<FileFailure[]>([])
  const error = ref('')
  const loading = ref(false)
  const pendingActions = ref<string[]>([])
  const batchResult = ref<BatchResult | null>(null)

  const tasks = computed(() => taskState.value.tasks)
  const activeCount = computed(() => tasks.value.filter(isActiveDownload).length)

  let port: NativeDownloadPort | undefined
  let dispose: (() => void) | undefined
  let connectionVersion = 0

  function detach(): void {
    connectionVersion += 1
    dispose?.()
    dispose = undefined
    port = undefined
    loading.value = false
  }

  async function attach(next: NativeDownloadPort): Promise<void> {
    detach()
    port = next
    const currentConnectionVersion = connectionVersion
    loading.value = true
    error.value = ''

    // The new observer takes a complete snapshot; events from a detached observer
    // are ignored by its connection version even if native unsubscribe completes later.
    resetDownloadObservation(taskState.value)

    try {
      const unsubscribe = await next.subscribeEvents((event) => {
        if (currentConnectionVersion !== connectionVersion) {
          return
        }

        const previousEpoch = taskState.value.epoch
        applyDownloadEvent(taskState.value, event)
        if (previousEpoch !== null && taskState.value.epoch !== previousEpoch) {
          void next
            .snapshot()
            .then((snapshot) => {
              if (currentConnectionVersion === connectionVersion) {
                applyDownloadSnapshot(taskState.value, snapshot)
              }
            })
            .catch((cause) => {
              if (currentConnectionVersion === connectionVersion) {
                error.value = errorMessage(cause)
              }
            })
        }
      })
      if (currentConnectionVersion !== connectionVersion) {
        unsubscribe()

        return
      }

      dispose = unsubscribe
      const snapshot = await next.snapshot()
      if (currentConnectionVersion === connectionVersion) {
        applyDownloadSnapshot(taskState.value, snapshot)
      }
    } catch (cause) {
      if (currentConnectionVersion === connectionVersion) {
        dispose?.()
        dispose = undefined
        error.value = errorMessage(cause)
      }
    } finally {
      if (currentConnectionVersion === connectionVersion) {
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
    const currentConnectionVersion = connectionVersion
    const captured = targets.map((target) => ({ ...target }))

    for (const target of captured) {
      const task = tasks.value.find((value) => value.id === target.taskId)
      if (
        !source ||
        connectionVersion !== currentConnectionVersion ||
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
          if (currentConnectionVersion === connectionVersion) {
            applyDownloadCommandResult(taskState.value, task.id, action, response)
          }
        }
      } catch (cause) {
        result.failures.push({ taskId: target.taskId, message: errorMessage(cause) })
      } finally {
        pendingActions.value = pendingActions.value.filter((id) => id !== target.taskId)
      }
    }

    if (connectionVersion === currentConnectionVersion) {
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
