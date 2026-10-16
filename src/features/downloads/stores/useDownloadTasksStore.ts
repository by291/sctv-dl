import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

import { errorMessage } from '@/shared/utils/errors'

import type {
  DownloadRequest,
  DownloadStartResult,
  DownloadTask,
  FileFailure,
} from '@shared/contracts/downloads'
import type { NativeDownloadPort } from '@/shared/platform/ports'

function terminal(task: DownloadTask): boolean {
  return task.state === 'completed' || task.state === 'failed' || task.state === 'cancelled'
}

export const useDownloadTasksStore = defineStore('downloadTasks', () => {
  const tasks = ref<DownloadTask[]>([])
  const failures = ref<FileFailure[]>([])
  const error = ref('')
  const loading = ref(false)
  const pendingActions = ref<string[]>([])

  const activeCount = computed(() => tasks.value.filter((task) => !terminal(task)).length)

  let port: NativeDownloadPort | undefined
  let dispose: (() => void) | undefined
  let generation = 0

  function merge(task: DownloadTask) {
    const index = tasks.value.findIndex((value) => value.id === task.id)
    const previous = tasks.value[index]

    // A delayed snapshot cannot roll back an event, and retries always receive a new task ID.
    if (previous && (previous.revision >= task.revision || terminal(previous))) {
      return
    }

    if (index < 0) {
      tasks.value.push(task)
    } else {
      tasks.value[index] = task
    }
  }

  function detach() {
    generation += 1
    dispose?.()
    dispose = undefined
    port = undefined
    loading.value = false
  }

  async function attach(next: NativeDownloadPort) {
    detach()
    port = next
    const current = generation
    loading.value = true
    error.value = ''

    try {
      // Subscribe before listing so work completed during hydration is retained by merge().
      const unsubscribe = await next.subscribe((task) => {
        if (current === generation) {
          merge(task)
        }
      })
      if (current !== generation) {
        unsubscribe()

        return
      }

      dispose = unsubscribe
      const snapshot = await next.list()
      if (current === generation) {
        snapshot.forEach(merge)
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

  async function start(
    request: DownloadRequest,
    source: NativeDownloadPort | undefined = port,
  ): Promise<DownloadStartResult> {
    if (!source) {
      throw new Error('桌面下载服务尚未连接')
    }

    // Initial downloads may start before the lazily loaded task panel attaches its observer.
    const result = await source.start(request)
    recordStart(result)

    return result
  }

  function recordStart(result: DownloadStartResult) {
    if (result.kind === 'native') {
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
  }

  async function action(id: string, run: () => Promise<unknown>) {
    if (pendingActions.value.includes(id)) {
      return
    }

    pendingActions.value.push(id)
    error.value = ''
    try {
      await run()
    } catch (cause) {
      error.value = errorMessage(cause)
    } finally {
      pendingActions.value = pendingActions.value.filter((value) => value !== id)
    }
  }

  async function cancel(id: string) {
    const current = port
    if (current) {
      await action(id, () => current.cancel(id))
    }
  }

  async function retry(id: string) {
    const task = tasks.value.find((value) => value.id === id)
    if (task && (task.state === 'failed' || task.state === 'cancelled')) {
      await action(id, () =>
        start({
          programmeId: task.content.programmeId,
          dateId: task.content.dateId,
          contentIds: [task.content.contentId],
          quality: task.quality,
        }),
      )
    }
  }

  return {
    tasks,
    failures,
    error,
    loading,
    pendingActions,
    activeCount,
    attach,
    detach,
    start,
    cancel,
    retry,
  }
})
