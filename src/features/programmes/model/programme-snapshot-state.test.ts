import { describe, expect, it } from 'vitest'
import {
  acceptProgrammeUpdate,
  receiveProgrammeSnapshot,
} from '@/features/programmes/model/programme-snapshot-state'
import type { ProgrammeSnapshot } from '@shared/contracts/programme-cache'

const snapshot: ProgrammeSnapshot = {
  kind: 'catalogue',
  version: 1,
  revision: '1',
  fetchedAt: '2026-10-17T00:00:00Z',
  items: [{ id: '1', name: 'News', cover: null }],
}

describe('accepted programme snapshots', () => {
  it('accepts an empty first snapshot and ignores a late cache read', () => {
    const initial = receiveProgrammeSnapshot(
      { accepted: null, pending: null },
      { ...snapshot, items: [] },
      'network',
    )
    expect(initial.accepted?.items).toEqual([])
    expect(receiveProgrammeSnapshot(initial, snapshot, 'cache')).toEqual(initial)
  })
  it('compares refreshed values with the visible snapshot instead of the pending revision', () => {
    const initial = { accepted: snapshot, pending: null }
    const changed = { ...snapshot, revision: '2', items: [{ id: '2', name: 'New', cover: null }] }
    const pending = receiveProgrammeSnapshot(initial, changed, 'network')
    expect(pending.accepted).toBe(snapshot)
    expect(pending.pending).toBe(changed)
    expect(
      receiveProgrammeSnapshot(pending, { ...changed, revision: '3' }, 'network').pending?.items,
    ).toEqual(changed.items)
    expect(
      receiveProgrammeSnapshot(pending, { ...snapshot, revision: '4' }, 'network').pending,
    ).toBeNull()
  })
  it('does not apply an update while a preview or selection holds it', () => {
    const state = { accepted: snapshot, pending: { ...snapshot, revision: '2', items: [] } }
    expect(acceptProgrammeUpdate(state, true)).toEqual(state)
    expect(acceptProgrammeUpdate(state, false)).toEqual({ accepted: state.pending, pending: null })
  })
})

it('keeps the visible list identity when only freshness advances', () => {
  const state = receiveProgrammeSnapshot(
    { accepted: snapshot, pending: null },
    {
      ...snapshot,
      items: snapshot.items.map((item) => ({ ...item })),
      fetchedAt: '2026-10-18T00:00:00Z',
    },
    'network',
  )
  expect(state.accepted?.items).toBe(snapshot.items)
  expect(state.accepted?.fetchedAt).toBe('2026-10-18T00:00:00Z')
})
