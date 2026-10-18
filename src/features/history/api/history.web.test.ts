import { IDBFactory, IDBObjectStore } from 'fake-indexeddb'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createApplicationDatabase } from '@/shared/storage/application-database.web'
import { createWebHistory } from '@/features/history/api/history.web'

const metadata = {
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  programmeName: 'News',
  broadcastDate: '2026-10-17',
  title: 'Episode',
  cover: null,
}
const sample = { positionMs: 300000, durationMs: 600000, ended: false, sequence: 1 }
const cleanup: Array<() => void> = []

function repository() {
  const database = createApplicationDatabase()
  const adapter = createWebHistory(database)
  cleanup.push(() => {
    adapter.dispose()
    database.dispose()
  })

  return adapter.port
}

beforeEach(() => {
  vi.stubGlobal('indexedDB', new IDBFactory())
  vi.stubGlobal('BroadcastChannel', undefined)
})
afterEach(() => {
  cleanup.splice(0).forEach((dispose) => dispose())
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('transactional browser viewing history', () => {
  it('persists the pending sample after a temporary quota failure without regressing other entries', async () => {
    const port = repository()
    const session = await port.begin(metadata)
    await port.record(session.id, sample)
    vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementationOnce(() => {
      throw new DOMException('Storage full', 'QuotaExceededError')
    })
    const pending = { ...sample, positionMs: 400000, sequence: 2 }
    expect((await port.record(session.id, pending)).persisted).toBe(false)
    const other = repository()
    const otherSession = await other.begin({
      ...metadata,
      content: { ...metadata.content, contentId: '4' },
    })
    await other.record(otherSession.id, sample)

    expect((await port.record(session.id, pending)).persisted).toBe(true)
    await port.flush()
    expect(
      (await repository().list()).entries.map((entry) => [
        entry.content.contentId,
        entry.positionMs,
      ]),
    ).toEqual([
      ['3', 400000],
      ['4', 300000],
    ])
  })

  it('discards fallback progress when another tab deletes its durable session', async () => {
    const port = repository()
    const session = await port.begin(metadata)
    await port.record(session.id, sample)
    vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementationOnce(() => {
      throw new DOMException('Storage full', 'QuotaExceededError')
    })
    const pending = { ...sample, positionMs: 400000, sequence: 2 }
    await port.record(session.id, pending)
    await repository().remove(metadata.content)

    expect(await port.record(session.id, pending)).toEqual({ accepted: false, persisted: true })
    expect((await port.list()).entries).toEqual([])
    expect((await repository().list()).entries).toEqual([])
  })

  it('observes another tab deletion even while writes still exceed quota', async () => {
    const port = repository()
    const session = await port.begin(metadata)
    await port.record(session.id, sample)
    const quota = vi.spyOn(IDBObjectStore.prototype, 'put')
    quota.mockImplementationOnce(() => {
      throw new DOMException('Storage full', 'QuotaExceededError')
    })
    await port.record(session.id, { ...sample, sequence: 2 })
    await repository().clear()
    quota.mockImplementation(() => {
      throw new DOMException('Storage full', 'QuotaExceededError')
    })

    expect((await port.record(session.id, { ...sample, sequence: 3 })).accepted).toBe(false)
    expect((await port.list()).entries).toEqual([])
  })

  it('recovers session-only progress when storage becomes available', async () => {
    vi.stubGlobal('indexedDB', undefined)
    const port = repository()
    const session = await port.begin(metadata)
    await port.record(session.id, sample)
    vi.stubGlobal('indexedDB', new IDBFactory())

    expect((await port.record(session.id, sample)).persisted).toBe(true)
    expect((await repository().list()).entries[0]?.positionMs).toBe(300000)
  })

  it('does not reinstall a failed begin after another tab opened and ended that content', async () => {
    vi.spyOn(IDBObjectStore.prototype, 'put').mockImplementationOnce(() => {
      throw new DOMException('Storage full', 'QuotaExceededError')
    })
    const port = repository()
    const old = await port.begin(metadata)
    const other = repository()
    const newer = await other.begin(metadata)
    await other.end(newer.id)

    expect(await port.record(old.id, sample)).toEqual({ accepted: false, persisted: true })
    expect((await repository().list()).entries).toEqual([])
  })

  it('keeps progress on begin and reload and rejects late samples from other tabs', async () => {
    const first = repository()
    const second = repository()
    const session = await first.begin(metadata)
    expect(await first.record(session.id, sample)).toEqual({ accepted: true, persisted: true })
    const newer = await second.begin(metadata)
    expect(newer.entry?.positionMs).toBe(300000)
    expect(
      (await first.record(session.id, { ...sample, positionMs: 400000, sequence: 2 })).accepted,
    ).toBe(false)
    await second.record(newer.id, { ...sample, positionMs: 350000, sequence: 2 })
    expect((await second.record(newer.id, sample)).accepted).toBe(false)
    expect((await repository().list()).entries[0]?.positionMs).toBe(350000)
  })

  it('invalidates sessions on deletion and clear until explicitly reopened', async () => {
    const port = repository()
    let session = await port.begin(metadata)
    await port.record(session.id, sample)
    await repository().remove(metadata.content)
    expect((await port.record(session.id, { ...sample, sequence: 2 })).accepted).toBe(false)
    expect((await port.list()).entries).toEqual([])
    session = await port.begin(metadata)
    await port.record(session.id, sample)
    await repository().clear()
    expect((await port.record(session.id, { ...sample, sequence: 2 })).accepted).toBe(false)
    expect((await port.list()).entries).toEqual([])
  })

  it('ends capture ownership and keeps the newest 500 content records', async () => {
    const database = createApplicationDatabase()
    cleanup.push(() => database.dispose())
    const connection = await database.open()
    await new Promise<void>((resolve, reject) => {
      const transaction = connection.transaction('history', 'readwrite')
      for (let index = 0; index < 500; index += 1) {
        transaction.objectStore('history').put(
          {
            ...metadata,
            content: { ...metadata.content, contentId: String(index) },
            positionMs: 1,
            durationMs: 600000,
            completed: false,
            viewedAt: new Date(index).toISOString(),
          },
          JSON.stringify(['1', '2', String(index)]),
        )
      }

      transaction.oncomplete = () => resolve()
      transaction.onabort = () => reject(transaction.error)
    })
    const port = repository()
    const last = await port.begin({
      ...metadata,
      content: { ...metadata.content, contentId: '500' },
    })
    await port.record(last.id, sample)
    await port.end(last.id)
    const snapshot = await port.list()
    expect(snapshot.entries).toHaveLength(500)
    expect(snapshot.entries[0]?.content.contentId).toBe('500')
    expect(snapshot.entries.some((entry) => entry.content.contentId === '0')).toBe(false)
    const session = await port.begin(metadata)
    await port.end(session.id)
    expect((await port.record(session.id, sample)).accepted).toBe(false)
  })

  it('uses explicit session-only storage on denied IndexedDB and fails durable flush', async () => {
    vi.stubGlobal('indexedDB', undefined)
    const port = repository()
    const session = await port.begin(metadata)
    expect(await port.record(session.id, sample)).toEqual({ accepted: true, persisted: false })
    const snapshot = await port.list()
    expect(snapshot.entries[0]?.positionMs).toBe(300000)
    expect(snapshot.persisted).toBe(false)
    expect(snapshot.warning).toBeTruthy()
    await expect(port.flush()).rejects.toThrow()
  })

  it('notifies committed snapshots and drains a write queued while flushing', async () => {
    const port = repository()
    const observe = vi.fn()
    const unsubscribe = await port.subscribe(observe)
    const session = await port.begin(metadata)
    const revision = port.getWriteRevision()
    const pending = port.record(session.id, sample)
    const flush = port.flush()
    const next = port.record(session.id, { ...sample, sequence: 2, positionMs: 400000 })
    expect(port.getWriteRevision()).toBe(revision + 2)
    await Promise.all([pending, next, flush])
    expect(observe.mock.lastCall?.[0].entries[0]?.positionMs).toBe(400000)
    unsubscribe()
  })
})
