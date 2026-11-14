import { sameProgrammePayload } from '@/features/programmes/model/cache-policy'
import type { ProgrammeSnapshot } from '@shared/contracts/programme-cache'

export interface ProgrammeSnapshotState<T extends ProgrammeSnapshot> {
  accepted: T | null
  pending: T | null
}

// Accept a snapshot or hold a changed payload for explicit application.
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

// Apply the pending snapshot when the current interaction permits it.
export function acceptProgrammeUpdate<T extends ProgrammeSnapshot>(
  state: ProgrammeSnapshotState<T>,
  { isInteractionHeld }: { isInteractionHeld: boolean },
): ProgrammeSnapshotState<T> {
  return isInteractionHeld || !state.pending ? state : { accepted: state.pending, pending: null }
}
