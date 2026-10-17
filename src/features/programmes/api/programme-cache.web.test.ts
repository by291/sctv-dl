import { IDBFactory } from 'fake-indexeddb'
import { programmeCacheKey } from '@shared/contracts/programme-cache'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createApplicationDatabase } from '@/shared/storage/application-database.web'
import { createWebProgrammeCache } from '@/features/programmes/api/programme-cache.web'
import { MAX_CACHE_BYTES } from '@/features/programmes/model/cache-policy'

const owners: Array<{ dispose(): void }> = []
beforeEach(() => {
  vi.stubGlobal('indexedDB', new IDBFactory())
})
afterEach(() => {
  owners.reverse().forEach((owner) => owner.dispose())
  owners.length = 0
  vi.unstubAllGlobals()
})

function setup() {
  const database = createApplicationDatabase()
  const cache = createWebProgrammeCache(database)
  owners.push(database, cache)

  return { database, cache: cache.port }
}

const browse = (id: number) => ({
  programmeId: String(id),
  dateId: null,
  date: null,
  sort: 'asc' as const,
  scrollY: id,
  visitedAt: new Date(id).toISOString(),
})

describe('browser programme cache', () => {
  it('distinguishes missing, valid empty and corrupt rows and retains revisions on equal refresh', async () => {
    const { database, cache } = setup()
    const initial = await cache.read({ kind: 'catalogue' })
    expect(initial.snapshot).toBeNull()
    const first = await cache.write({ kind: 'catalogue', items: [] }, initial.epoch)
    const again = await cache.write({ kind: 'catalogue', items: [] }, initial.epoch)
    expect(again.snapshot?.revision).toBe(first.snapshot?.revision)
    expect((await cache.read({ kind: 'catalogue' })).snapshot?.items).toEqual([])
    const connection = await database.open()
    await new Promise<void>((resolve) => {
      const tx = connection.transaction('programmeCache', 'readwrite')
      tx.objectStore('programmeCache').put(
        { epoch: initial.epoch, snapshot: { bad: true } },
        'catalogue',
      )
      tx.oncomplete = () => resolve()
    })
    expect((await cache.read({ kind: 'catalogue' })).snapshot).toBeNull()
    expect((await cache.write({ kind: 'catalogue', items: [] }, initial.epoch)).persisted).toBe(
      true,
    )
  })
  it('evicts least recently accessed snapshots and bounds browse records independently', async () => {
    const { cache, database } = setup()
    const { epoch } = await cache.read({ kind: 'catalogue' })
    const connection = await database.open()
    // Seed the capacity boundary in one transaction; exercise eviction through the public port.
    await new Promise<void>((resolve, reject) => {
      const tx = connection.transaction(['programmeCache', 'browseState'], 'readwrite')
      for (let id = 0; id < 200; id++) {
        const snapshot = {
          kind: 'dates' as const,
          programmeId: String(id),
          items: [],
          version: 1,
          revision: crypto.randomUUID(),
          fetchedAt: new Date(id).toISOString(),
        }
        tx.objectStore('programmeCache').put(
          { epoch, snapshot, accessed: id },
          programmeCacheKey(snapshot),
        )
      }

      for (let id = 0; id < 100; id++) {
        tx.objectStore('browseState').put({ epoch, value: browse(id) }, String(id))
      }

      tx.oncomplete = () => resolve()
      tx.onabort = () => reject(tx.error)
    })

    await cache.read({ kind: 'dates', programmeId: '0' })
    await cache.write({ kind: 'dates', programmeId: '200', items: [] }, epoch)
    expect((await cache.read({ kind: 'dates', programmeId: '1' })).snapshot).toBeNull()
    expect((await cache.read({ kind: 'dates', programmeId: '0' })).snapshot).not.toBeNull()
    await cache.writeBrowseState(browse(100), epoch)

    expect((await cache.readBrowseState('0')).value).toBeNull()
    expect((await cache.readBrowseState('100')).value?.scrollY).toBe(100)
  })
  it('counts multibyte titles and keeps an oversized result usable without replacing disk data', async () => {
    const { cache } = setup()
    const { epoch } = await cache.read({ kind: 'catalogue' })
    await cache.write({ kind: 'catalogue', items: [] }, epoch)
    const large = await cache.write(
      {
        kind: 'catalogue',
        items: [{ id: '1', name: '川'.repeat(Math.ceil(MAX_CACHE_BYTES / 3)), cover: null }],
      },
      epoch,
    )
    expect(large.accepted).toBe(true)
    expect(large.persisted).toBe(false)
    expect(large.warning).toBeTruthy()
    expect(large.snapshot?.items).toHaveLength(1)
    expect((await cache.read({ kind: 'catalogue' })).snapshot?.items).toEqual([])
    const title = '川'.repeat(2_400_000)
    for (let id = 0; id < 3; id++) {
      await cache.write(
        {
          kind: 'contents',
          programmeId: '1',
          dateId: String(id),
          items: [
            { id: '1', title, cover: null, video: null, smoothVideo: null, publishedAt: null },
          ],
        },
        epoch,
      )
    }

    expect(
      (await cache.read({ kind: 'contents', programmeId: '1', dateId: '0' })).snapshot,
    ).toBeNull()
  })
  it('fences stale writes across connections and preserves unrelated stores', async () => {
    const a = setup()
    const b = setup()
    const { epoch } = await a.cache.read({ kind: 'catalogue' })
    await a.cache.writeBrowseState(browse(1), epoch)
    const connection = await a.database.open()
    await new Promise<void>((resolve) => {
      const tx = connection.transaction('history', 'readwrite')
      tx.objectStore('history').put('preserve', 'history')
      tx.oncomplete = () => resolve()
    })
    const cleared = await b.cache.clear()
    expect(cleared.epoch).not.toBe(epoch)
    expect((await a.cache.write({ kind: 'catalogue', items: [] }, epoch)).accepted).toBe(false)
    expect((await a.cache.writeBrowseState(browse(2), epoch)).accepted).toBe(false)
    expect((await a.cache.write({ kind: 'catalogue', items: [] }, cleared.epoch)).persisted).toBe(
      true,
    )
    expect((await b.cache.readBrowseState('1')).value).toBeNull()
    const request = connection.transaction('history').objectStore('history').get('history')
    expect(
      await new Promise((resolve) => {
        request.onsuccess = () => resolve(request.result)
      }),
    ).toBe('preserve')
  })
  it('keeps a bounded memory cache when the database cannot open', async () => {
    const owner = createWebProgrammeCache({
      open: () => Promise.reject(new Error('denied')),
      dispose() {},
    })
    owners.push(owner)
    const initial = await owner.port.read({ kind: 'catalogue' })
    const result = await owner.port.write({ kind: 'catalogue', items: [] }, initial.epoch)
    expect(result.persisted).toBe(false)
    expect(result.warning).toBeTruthy()
    expect((await owner.port.read({ kind: 'catalogue' })).snapshot?.items).toEqual([])
  })
})

it('keeps the committed epoch after cleanup failure and preserves concurrent writes in the new epoch', async () => {
  const a = setup()
  const b = setup()
  const { epoch: old } = await a.cache.read({ kind: 'catalogue' })
  await a.cache.write({ kind: 'catalogue', items: [] }, old)
  const connection = await a.database.open()
  const transaction = connection.transaction.bind(connection)
  const fail = vi.spyOn(connection, 'transaction').mockImplementation((stores, mode, options) => {
    if (Array.isArray(stores)) {
      throw new Error('Cleanup denied')
    }

    return transaction(stores, mode, options)
  })
  await expect(a.cache.clear()).rejects.toThrow('Cleanup denied')
  fail.mockRestore()
  const current = await b.cache.read({ kind: 'catalogue' })
  expect(current.epoch).not.toBe(old)
  expect(current.snapshot).toBeNull()
  expect((await a.cache.write({ kind: 'catalogue', items: [] }, old)).accepted).toBe(false)
  let newWrite: Promise<unknown> | undefined
  const stop = await a.cache.subscribeCleared((epoch) => {
    newWrite = b.cache.write({ kind: 'catalogue', items: [] }, epoch)
  })
  const cleared = await a.cache.clear()
  await newWrite
  stop()
  expect((await a.cache.read({ kind: 'catalogue' })).epoch).toBe(cleared.epoch)
  expect((await a.cache.read({ kind: 'catalogue' })).snapshot?.items).toEqual([])
})

it('retains a memory-only snapshot after a quota failure and retries it without losing the epoch fence', async () => {
  const { database, cache } = setup()
  const { epoch } = await cache.read({ kind: 'catalogue' })
  const connection = await database.open()
  const transaction = connection.transaction.bind(connection)
  const fail = vi.spyOn(connection, 'transaction').mockImplementation((stores, mode, options) => {
    const tx = transaction(stores, mode, options)
    if (Array.isArray(stores)) {
      const store = tx.objectStore('programmeCache')
      vi.spyOn(store, 'put').mockImplementation(() => {
        throw new DOMException('Quota exceeded', 'QuotaExceededError')
      })
      const objectStore = tx.objectStore.bind(tx)
      vi.spyOn(tx, 'objectStore').mockImplementation((name) =>
        name === 'programmeCache' ? store : objectStore(name),
      )
    }

    return tx
  })
  expect((await cache.write({ kind: 'catalogue', items: [] }, epoch)).persisted).toBe(false)
  expect((await cache.read({ kind: 'catalogue' })).snapshot?.items).toEqual([])
  fail.mockRestore()
  expect((await cache.read({ kind: 'catalogue' })).snapshot?.items).toEqual([])
})

it('does not report opening an existing cache as a clear and releases subscriptions on disposal', async () => {
  const first = setup()
  await first.cache.read({ kind: 'catalogue' })
  const second = setup()
  const listener = vi.fn()
  const stop = await second.cache.subscribeCleared(listener)
  await second.cache.read({ kind: 'catalogue' })
  expect(listener).not.toHaveBeenCalled()
  await second.cache.clear()
  expect(listener).toHaveBeenCalledTimes(1)
  stop()
  await second.cache.clear()
  expect(listener).toHaveBeenCalledTimes(1)
})
