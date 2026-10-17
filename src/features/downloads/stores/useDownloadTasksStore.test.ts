// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import {
  createDownloadTaskFixture,
  createNativeDownloadFixture,
} from '@/shared/platform/platform.test-support'

import type { DownloadEvent, DownloadSnapshot } from '@shared/contracts/downloads'

beforeEach(() => setActivePinia(createPinia()))
const task = createDownloadTaskFixture()

it('starts before observation and retains per-file failures', async () => {
  const port = createNativeDownloadFixture()
  port.start = async () => ({
    kind: 'native',
    taskIds: ['job'],
    usedFallback: true,
    failures: [{ contentId: '4', message: 'Missing content' }],
  })
  const store = useDownloadTasksStore()
  await store.start(
    { programmeId: '1', dateId: '2', contentIds: ['3', '4'], quality: 'smooth' },
    port,
  )
  expect(store.failures).toEqual([{ contentId: '4', message: 'Missing content' }])
})

it('subscribes before listing and does not resurrect a removed task from a delayed snapshot', async () => {
  const port = createNativeDownloadFixture()
  let receive!: (event: DownloadEvent) => void
  let finish!: (snapshot: DownloadSnapshot) => void
  port.subscribeEvents = async (listener) => {
    receive = listener

    return () => {}
  }

  port.snapshot = () =>
    new Promise((resolve) => {
      finish = resolve
    })
  const store = useDownloadTasksStore()
  const pending = store.attach(port)
  await Promise.resolve()
  receive({ kind: 'remove', epoch: 'one', revision: 5, taskId: task.id })
  finish({ epoch: 'one', revision: 4, tasks: [task] })
  await pending
  expect(store.tasks).toEqual([])
  receive({ kind: 'upsert', epoch: 'one', revision: 3, task })
  expect(store.tasks).toEqual([])
})

it('accepts a newer attempt after a terminal state and ignores a retired process epoch', async () => {
  const port = createNativeDownloadFixture()
  let receive!: (event: DownloadEvent) => void
  port.subscribeEvents = async (listener) => {
    receive = listener

    return () => {}
  }

  port.snapshot = async () => ({ epoch: 'one', revision: 2, tasks: [{ ...task, state: 'failed' }] })
  const store = useDownloadTasksStore()
  await store.attach(port)
  receive({
    kind: 'upsert',
    epoch: 'one',
    revision: 3,
    task: { ...task, attemptId: 'next', revision: 3 },
  })
  expect(store.tasks[0]?.attemptId).toBe('next')
  port.snapshot = async () => ({ epoch: 'two', revision: 1, tasks: [] })
  receive({ kind: 'upsert', epoch: 'two', revision: 2, task: { ...task, state: 'interrupted' } })
  receive({ kind: 'upsert', epoch: 'one', revision: 100, task })
  expect(store.tasks[0]?.state).toBe('interrupted')
  expect(store.activeCount).toBe(0)
})

it('cleans up a late observer after detachment', async () => {
  const port = createNativeDownloadFixture()
  let finish!: (dispose: () => void) => void
  port.subscribeEvents = () =>
    new Promise((resolve) => {
      finish = resolve
    })
  const store = useDownloadTasksStore()
  const pending = store.attach(port)
  store.detach()
  const stop = vi.fn()
  finish(stop)
  await pending
  expect(stop).toHaveBeenCalledOnce()
})

it('snapshots batch attempts, skips changed tasks and continues after independent failure', async () => {
  const port = createNativeDownloadFixture()
  const tasks = [task, { ...task, id: 'second' }, { ...task, id: 'third' }]
  port.snapshot = async () => ({ epoch: 'one', revision: 2, tasks })
  port.act = vi.fn(async (request) => {
    if (request.taskId === 'second') {
      throw new Error('Disk unavailable')
    }

    return { kind: 'applied' as const, task: { ...task, state: 'paused' as const, revision: 3 } }
  })
  const store = useDownloadTasksStore()
  await store.attach(port)
  const result = await store.runBatch(
    'pause',
    tasks.map((value) => ({
      taskId: value.id,
      attemptId: value.id === 'third' ? 'old' : value.attemptId,
    })),
  )
  expect(result).toEqual({
    applied: 1,
    skipped: 1,
    failures: [{ taskId: 'second', message: 'Disk unavailable' }],
  })
  expect(port.act).toHaveBeenCalledTimes(2)
})
