import { IDBFactory } from 'fake-indexeddb'
import { afterEach, expect, it, vi } from 'vitest'

import { createApplicationDatabase } from '@/shared/storage/application-database.web'

afterEach(() => vi.unstubAllGlobals())

it('shares one connection with the history and metadata stores and closes it on disposal', async () => {
  vi.stubGlobal('indexedDB', new IDBFactory())
  const owner = createApplicationDatabase()
  const database = await owner.open()
  expect(await owner.open()).toBe(database)
  expect([...database.objectStoreNames]).toEqual([
    'browseState',
    'history',
    'historySessions',
    'meta',
    'programmeCache',
  ])
  owner.dispose()
  await expect(owner.open()).rejects.toThrow()
  expect(() => database.transaction('history')).toThrow()
})

it('reports unavailable storage without leaving an open connection', async () => {
  vi.stubGlobal('indexedDB', undefined)
  const owner = createApplicationDatabase()
  await expect(owner.open()).rejects.toThrow()
  owner.dispose()
})

it('retries opening after a temporary storage denial', async () => {
  vi.stubGlobal('indexedDB', undefined)
  const owner = createApplicationDatabase()
  await expect(owner.open()).rejects.toThrow()
  vi.stubGlobal('indexedDB', new IDBFactory())
  expect((await owner.open()).objectStoreNames.contains('history')).toBe(true)
  owner.dispose()
})
