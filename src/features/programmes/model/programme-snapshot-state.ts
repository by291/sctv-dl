import { sameProgrammePayload } from '@/features/programmes/model/cache-policy'
import type { ProgrammeSnapshot } from '@shared/contracts/programme-cache'

export interface ProgrammeSnapshotState<T extends ProgrammeSnapshot> {
  accepted: T | null
  pending: T | null
}

export function receiveProgrammeSnapshot<T extends ProgrammeSnapshot>(
  state: ProgrammeSnapshotState<T>,
  next: T,
  source: 'cache' | 'network',
): ProgrammeSnapshotState<T> {
  if (source === 'cache' && state.accepted) {
    return state
  }

  if (!state.accepted) {
    return { accepted: next, pending: null }
  }

  if (sameProgrammePayload(state.accepted, next)) {
    return { accepted: { ...next, items: state.accepted.items }, pending: null }
  }

  return { accepted: state.accepted, pending: next }
}

export function acceptProgrammeUpdate<T extends ProgrammeSnapshot>(
  state: ProgrammeSnapshotState<T>,
  held: boolean,
): ProgrammeSnapshotState<T> {
  return held || !state.pending ? state : { accepted: state.pending, pending: null }
}
