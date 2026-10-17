import { expect, it, vi } from 'vitest'

import { flushPersistence } from '@/platform/persistence-lifecycle'

it('drains again when another owner queues a save during persistence checks', async () => {
  let revision = 1
  const flush = vi.fn(async () => {})
  const persisted = vi.fn(async () => {
    if (revision === 1) {
      revision += 1
    }

    return true
  })
  expect(
    await flushPersistence([{ getWriteRevision: () => revision, flush, isPersisted: persisted }]),
  ).toBe(true)
  expect(flush).toHaveBeenCalledTimes(2)
})

it('reports an incomplete exit save when either persistence owner fails', async () => {
  expect(
    await flushPersistence([
      {
        getWriteRevision: () => 0,
        flush: async () => {
          throw new Error('quota')
        },
        isPersisted: async () => true,
      },
    ]),
  ).toBe(false)
  expect(
    await flushPersistence([
      { getWriteRevision: () => 0, flush: async () => {}, isPersisted: async () => false },
    ]),
  ).toBe(false)
})
