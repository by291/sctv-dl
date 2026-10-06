import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { errorMessage } from '../../shared/errors'
import { usePersistentState } from '../../shared/storage'
import { handOffDownload } from './browser-download'
import { appendTasks, recoverInterruptedTasks } from './model'
import { downloadTasksSchema } from './schema'

import type { DownloadTask } from './schema'

export const useDownloadStore = defineStore('downloads', () => {
  // Execute per window; cross-window syncing could mistake another window's check for an interruption.
  const { value: tasks, persisted } = usePersistentState<DownloadTask[]>(
    'sctv-dl:downloads',
    [],
    downloadTasksSchema,
    { syncTabs: false },
  )
  tasks.value = recoverInterruptedTasks(tasks.value)

  const batchRunning = ref(false)
  const pending = computed(() =>
    tasks.value.filter((task) => task.status === 'queued' || task.status === 'failed'),
  )

  function add(added: DownloadTask[]) {
    const before = tasks.value.length
    tasks.value = appendTasks(tasks.value, added)

    return tasks.value.length - before
  }

  function remove(id: string) {
    tasks.value = tasks.value.filter((task) => task.id !== id || task.status === 'checking')
  }

  function clearHistory() {
    tasks.value = tasks.value.filter((task) => task.status !== 'handed-off')
  }

  async function start(id: string) {
    const task = tasks.value.find((task) => task.id === id)

    if (!task || task.status === 'checking') {
      return
    }

    task.status = 'checking'
    task.error = undefined

    try {
      await handOffDownload(task)
      task.status = 'handed-off'
    } catch (cause) {
      task.status = 'failed'
      task.error = errorMessage(cause)
    }
  }

  async function startQueued() {
    if (batchRunning.value) {
      return
    }

    batchRunning.value = true

    try {
      for (const task of [...pending.value]) {
        await start(task.id)
      }
    } finally {
      batchRunning.value = false
    }
  }

  return { tasks, pending, batchRunning, persisted, add, remove, clearHistory, start, startQueued }
})
