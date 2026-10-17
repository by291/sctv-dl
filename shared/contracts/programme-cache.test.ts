import { describe, expect, it } from 'vitest'
import fixture from '../fixtures/programme-cache.json' with { type: 'json' }
import { archiveBrowseStateSchema, programmeSnapshotSchema } from './programme-cache.ts'

describe('programme cache contracts', () => {
  it('accepts the shared valid-empty snapshot and rejects malformed keys and dates', () => {
    expect(programmeSnapshotSchema.parse(fixture.snapshot).items).toEqual([])
    expect(
      programmeSnapshotSchema.safeParse({ ...fixture.snapshot, programmeId: '../1', kind: 'dates' })
        .success,
    ).toBe(false)
    expect(
      programmeSnapshotSchema.safeParse({ ...fixture.snapshot, fetchedAt: 'yesterday' }).success,
    ).toBe(false)
    expect(
      archiveBrowseStateSchema.safeParse({ ...fixture.browse, scrollY: Infinity }).success,
    ).toBe(false)
  })
})
