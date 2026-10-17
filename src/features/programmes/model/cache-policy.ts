import { programmeCachePayloadSchema } from '@shared/contracts/programme-cache'
import type { ProgrammeSnapshot } from '@shared/contracts/programme-cache'

export const MAX_CACHE_SNAPSHOTS = 200

export const MAX_CACHE_BYTES = 20 * 1024 * 1024

export const MAX_BROWSE_STATES = 100

export function sameProgrammePayload(left: unknown, right: unknown): boolean {
  const a = programmeCachePayloadSchema.safeParse(left)
  const b = programmeCachePayloadSchema.safeParse(right)

  // Schema parsing strips unused properties and gives optional nullable fields a
  // canonical shape. Equality is never inferred solely from a revision/hash.
  return a.success && b.success && JSON.stringify(a.data) === JSON.stringify(b.data)
}

export function snapshotBytes(snapshot: ProgrammeSnapshot): number {
  return new TextEncoder().encode(JSON.stringify(snapshot)).byteLength
}
