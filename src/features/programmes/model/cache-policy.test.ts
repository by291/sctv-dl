import { describe, expect, it } from 'vitest'
import { sameProgrammePayload, snapshotBytes } from '@/features/programmes/model/cache-policy'
import { programmeSnapshotSchema } from '@shared/contracts/programme-cache'

describe('cache policy', () => {
  it('normalizes optional null fields and ignores JSON key order while preserving effective values and list order', () => {
    const left = {
      kind: 'catalogue',
      items: [
        { id: '1', name: '四川' },
        { id: '2', name: '新闻', cover: null },
      ],
    }
    const right = {
      items: [
        { name: '四川', cover: null, id: '1' },
        { cover: null, name: '新闻', id: '2' },
      ],
      kind: 'catalogue',
      unused: true,
    }
    expect(sameProgrammePayload(left, right)).toBe(true)
    expect(sameProgrammePayload(left, { ...right, items: [...right.items].reverse() })).toBe(false)
    expect(sameProgrammePayload(left, { ...right, items: [{ id: '1', name: 'changed' }] })).toBe(
      false,
    )
  })
  it('counts serialized UTF-8 bytes', () => {
    const snapshot = programmeSnapshotSchema.parse({
      kind: 'catalogue',
      items: [{ id: '1', name: '四川' }],
      version: 1,
      revision: 'r',
      fetchedAt: '2026-10-17T00:00:00.000Z',
    })
    expect(snapshotBytes(snapshot)).toBe(
      new TextEncoder().encode(JSON.stringify(snapshot)).byteLength,
    )
    expect(snapshotBytes(snapshot)).toBeGreaterThan(JSON.stringify(snapshot).length)
  })
})
