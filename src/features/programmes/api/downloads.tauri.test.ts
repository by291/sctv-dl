// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from 'vitest'
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
  bridge.invoke.mockResolvedValueOnce([{ ...task, totalBytes: -1 }])
  await expect(downloads.list()).rejects.toThrow()
  bridge.invoke.mockRejectedValueOnce({ code: 'storage', message: '目录不可写' })
  await expect(downloads.chooseDirectory()).rejects.toThrow('目录不可写')
})

it('delivers validated channel updates and disposes its native subscription once', async () => {
  bridge.invoke.mockResolvedValueOnce('subscription')
  const values: unknown[] = []
  const dispose = await createTauriDownloads().subscribe((value) => values.push(value))
  bridge.channels[0]!.onmessage(task)
  bridge.channels[0]!.onmessage({ ...task, state: 'invalid' })
  expect(values).toEqual([task])
  bridge.invoke.mockResolvedValue(undefined)
  dispose()
  dispose()
  bridge.channels[0]!.onmessage({ ...task, revision: 3 })
  expect(values).toHaveLength(1)
  expect(
    bridge.invoke.mock.calls.filter(([command]) => command === 'unsubscribe_downloads'),
  ).toEqual([['unsubscribe_downloads', { subscriptionId: 'subscription' }]])
})
