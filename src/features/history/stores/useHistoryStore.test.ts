import { beforeEach, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

import { useHistoryStore } from '@/features/history/stores/useHistoryStore'

import type { HistoryPort } from '@/shared/platform/ports'
import type { HistorySnapshot } from '@shared/contracts/history'

const entry = {
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  programmeName: 'News',
  broadcastDate: '2026-10-17',
  title: 'Episode',
  cover: null,
  positionMs: 3,
  durationMs: 30,
  completed: false,
  viewedAt: '2026-10-17T00:00:00Z',
}
const empty: HistorySnapshot = { entries: [], revision: 0, persisted: true, warning: null }

function port(): HistoryPort {
  return {
    list: async () => empty,
    begin: async () => ({ id: '1', entry: null }),
    record: async () => ({ accepted: true, persisted: true }),
    end: async () => {},
    remove: async () => {},
    clear: async () => {},
    subscribe: async () => () => {},
    flush: async () => {},
    getWriteRevision: () => 0,
  }
}

beforeEach(() => setActivePinia(createPinia()))

it('observes before loading and rejects an older hydration snapshot', async () => {
  const source = port()
  source.subscribe = async (listener) => {
    listener({ ...empty, entries: [entry], revision: 2 })

    return () => {}
  }

  const store = useHistoryStore()
  await store.attach(source)
  expect(store.entries).toEqual([entry])
})

it('disposes a subscription that resolves after detach', async () => {
  const source = port()
  let finish!: (stop: () => void) => void
  source.subscribe = () =>
    new Promise((resolve) => {
      finish = resolve
    })
  const store = useHistoryStore()
  const attached = store.attach(source)
  store.detach()
  const stop = vi.fn()
  finish(stop)
  await attached
  expect(stop).toHaveBeenCalledOnce()
  expect(store.loading).toBe(false)
})

it('captures each active player once and removes disposed players', async () => {
  const store = useHistoryStore()
  const capture = vi.fn(async () => {})
  const stop = store.registerCapture(capture)
  await store.captureActive()
  stop()
  await store.captureActive()
  expect(capture).toHaveBeenCalledOnce()
})

it('preserves records on a failed deletion and surfaces an actionable error', async () => {
  const source = port()
  source.list = async () => ({ ...empty, entries: [entry] })
  source.remove = async () => {
    throw new Error('Disk unavailable')
  }

  const store = useHistoryStore()
  await store.attach(source)
  await store.remove(entry.content)
  expect(store.entries).toEqual([entry])
  expect(store.error).toContain('Disk unavailable')
})
