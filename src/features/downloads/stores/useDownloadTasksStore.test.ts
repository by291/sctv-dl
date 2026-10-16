// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import type { DownloadTask } from '@shared/contracts/downloads'
import type { NativeDownloadPort } from '@/shared/platform/ports'

const task: DownloadTask = {
  id: 'job',
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  filename: 'clip.mp4',
  quality: 'standard',
  state: 'running',
  receivedBytes: 10,
  totalBytes: null,
  error: null,
  revision: 2,
}
beforeEach(() => {
  setActivePinia(createPinia())
})

it('subscribes before snapshot and retains a newer terminal event during hydration', async () => {
  let listener: (task: DownloadTask) => void = () => {}

  let resolveList: (tasks: DownloadTask[]) => void = () => {}

  const dispose = vi.fn()
  const order: string[] = []
  const port = {
    kind: 'native',
    subscribe: async (next: typeof listener) => {
      order.push('subscribe')
      listener = next

      return dispose
    },
    list: () => {
      order.push('list')

      return new Promise<DownloadTask[]>((resolve) => {
        resolveList = resolve
      })
    },
    start: vi.fn(),
    cancel: vi.fn(),
  } as unknown as NativeDownloadPort
  const store = useDownloadTasksStore()
  const attached = store.attach(port)
  await Promise.resolve()
  listener({ ...task, state: 'completed', revision: 3 })
  resolveList([task])
  await attached
  expect(order).toEqual(['subscribe', 'list'])
  expect(store.tasks[0]!.state).toBe('completed')
  listener({ ...task, state: 'running', revision: 4 })
  expect(store.tasks[0]!.state).toBe('completed')
  const detach = store.detach
  detach()
  detach()
  expect(dispose).toHaveBeenCalledOnce()
})

it('cleans up a late subscription and retries using the actual quality and reference', async () => {
  let resolveSubscription: (dispose: () => void) => void = () => {}

  const dispose = vi.fn()
  const start = vi.fn().mockResolvedValue({
    kind: 'native',
    taskIds: ['retry'],
    usedFallback: false,
    failures: [{ contentId: '4', message: 'Missing content' }],
  })
  const port = {
    kind: 'native',
    subscribe: () =>
      new Promise<() => void>((resolve) => {
        resolveSubscription = resolve
      }),
    list: vi.fn().mockResolvedValue([]),
    start,
    cancel: vi.fn(),
  } as unknown as NativeDownloadPort
  const store = useDownloadTasksStore()
  const pending = store.attach(port)
  store.detach()
  resolveSubscription(dispose)
  await pending
  expect(dispose).toHaveBeenCalledOnce()
  const active = {
    ...port,
    subscribe: async () => dispose,
    list: async () => [{ ...task, state: 'failed' as const, quality: 'smooth' as const }],
  }
  await store.attach(active)
  await store.retry('job')
  expect(start).toHaveBeenCalledWith({
    programmeId: '1',
    dateId: '2',
    contentIds: ['3'],
    quality: 'smooth',
  })
  expect(store.failures).toEqual([{ contentId: '4', message: 'Missing content' }])
  store.detach()
})
