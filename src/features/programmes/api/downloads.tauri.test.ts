// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from 'vitest'
import { createDownloadTaskFixture } from '@/shared/platform/platform.test-support'
import { createTauriDownloads } from '@/features/programmes/api/downloads.tauri'

const bridge = vi.hoisted(() => ({
  invoke: vi.fn(),
  channels: [] as { onmessage: (value: unknown) => void }[],
}))
vi.mock('@tauri-apps/api/core', () => ({
  invoke: bridge.invoke,
  Channel: class {
    onmessage: (value: unknown) => void = () => {}
    constructor() {
      bridge.channels.push(this)
    }
  },
}))
const task = {
  ...createDownloadTaskFixture(),
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
  bridge.invoke.mockReset()
  bridge.channels.length = 0
})

it('validates native results and sends only domain references to start', async () => {
  bridge.invoke.mockResolvedValueOnce({
    kind: 'native',
    taskIds: ['job'],
    failures: [],
    usedFallback: false,
  })
  const downloads = createTauriDownloads()
  expect(
    await downloads.start({
      programmeId: '1',
      dateId: '2',
      contentIds: ['3', '3'],
      quality: 'standard',
    }),
  ).toEqual({ kind: 'native', taskIds: ['job'], failures: [], usedFallback: false })
  expect(bridge.invoke).toHaveBeenCalledWith('start_downloads', {
    request: { programmeId: '1', dateId: '2', contentIds: ['3'], quality: 'standard' },
  })
  bridge.invoke.mockResolvedValueOnce({
    epoch: 'process',
    revision: 2,
    tasks: [{ ...task, totalBytes: -1 }],
  })
  await expect(downloads.snapshot()).rejects.toThrow()
  bridge.invoke.mockRejectedValueOnce({ code: 'storage', message: '目录不可写' })
  await expect(downloads.chooseDirectory()).rejects.toThrow('目录不可写')
})

it('delivers validated channel updates and disposes its native subscription once', async () => {
  bridge.invoke.mockResolvedValueOnce('subscription')
  const values: unknown[] = []
  const dispose = await createTauriDownloads().subscribeEvents((value) => values.push(value))
  const event = { kind: 'upsert', epoch: 'process', revision: 2, task }
  bridge.channels[0]!.onmessage(event)
  bridge.channels[0]!.onmessage({ ...event, task: { ...task, state: 'invalid' } })
  expect(values).toEqual([event])
  bridge.invoke.mockResolvedValue(undefined)
  dispose()
  dispose()
  bridge.channels[0]!.onmessage({ ...event, revision: 3 })
  expect(values).toHaveLength(1)
  expect(
    bridge.invoke.mock.calls.filter(([command]) => command === 'unsubscribe_download_events'),
  ).toEqual([['unsubscribe_download_events', { subscriptionId: 'subscription' }]])
})

it('carries attempts and removal revisions and opens only a task-owned local file', async () => {
  const downloads = createTauriDownloads()
  bridge.invoke.mockResolvedValueOnce({ epoch: 'process', revision: 4, tasks: [task] })
  expect((await downloads.snapshot()).tasks).toEqual([task])
  bridge.invoke.mockResolvedValueOnce({ kind: 'applied', task: { ...task, state: 'paused' } })
  await downloads.act({ taskId: task.id, attemptId: task.attemptId, action: 'pause' })
  expect(bridge.invoke).toHaveBeenLastCalledWith('act_on_download', {
    request: { taskId: task.id, attemptId: task.attemptId, action: 'pause' },
  })
  bridge.invoke.mockResolvedValueOnce('subscription')
  const events: unknown[] = []
  const stop = await downloads.subscribeEvents((event) => events.push(event))
  const removed = { kind: 'remove', epoch: 'process', revision: 5, taskId: task.id }
  bridge.channels[0]!.onmessage(removed)
  expect(events).toEqual([removed])
  bridge.invoke.mockResolvedValueOnce(null)
  stop()
  bridge.invoke.mockResolvedValueOnce({
    id: 'local',
    selectedQuality: 'standard',
    sources: [{ quality: 'standard', url: 'http://127.0.0.1:8000/opaque' }],
  })
  await downloads.openPlayback(task.id)
  expect(bridge.invoke).toHaveBeenLastCalledWith('open_local_playback', {
    taskId: task.id,
    requestId: expect.any(String),
  })
})
