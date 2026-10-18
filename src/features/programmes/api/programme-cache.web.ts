import { z } from 'zod'
import {
  archiveBrowseStateSchema,
  programmeCacheKey,
  programmeCachePayloadSchema,
  programmeSnapshotSchema,
} from '@shared/contracts/programme-cache'
import { idSchema } from '@shared/contracts/programmes'
import {
  MAX_BROWSE_STATES,
  MAX_CACHE_BYTES,
  MAX_CACHE_SNAPSHOTS,
  sameProgrammePayload,
  snapshotBytes,
} from '@/features/programmes/model/cache-policy'

import type { ArchiveBrowseState, ProgrammeSnapshot } from '@shared/contracts/programme-cache'
import type { ProgrammeCachePort } from '@/shared/platform/ports'
import type { ApplicationDatabase } from '@/shared/storage/application-database.web'

const snapshotRowSchema = z.object({
  epoch: z.string(),
  snapshot: programmeSnapshotSchema,
  accessed: z.number().finite(),
})
const browseRowSchema = z.object({ epoch: z.string(), value: archiveBrowseStateSchema })
type SnapshotRow = z.infer<typeof snapshotRowSchema>
type BrowseRow = z.infer<typeof browseRowSchema>
interface CacheState {
  epoch: string
  snapshots: Map<string, SnapshotRow>
  browse: Map<string, BrowseRow>
}
const storageWarning = '节目缓存无法保存到本地，当前数据仅在本次会话中保留'
const oversizedWarning = '节目数据超过缓存容量，本次结果未保存'

function decodeCacheState(
  storedEpoch: unknown,
  snapshots: unknown[],
  browse: unknown[],
  initialEpoch: string,
): CacheState {
  const epoch = typeof storedEpoch === 'string' && storedEpoch ? storedEpoch : initialEpoch
  const draft: CacheState = { epoch, snapshots: new Map(), browse: new Map() }
  for (const raw of snapshots) {
    const row = snapshotRowSchema.safeParse(raw)
    if (row.success && row.data.epoch === epoch) {
      draft.snapshots.set(programmeCacheKey(row.data.snapshot), row.data)
    }
  }

  for (const raw of browse) {
    const row = browseRowSchema.safeParse(raw)
    if (row.success && row.data.epoch === epoch) {
      draft.browse.set(row.data.value.programmeId, row.data)
    }
  }

  return draft
}

function mergeFallbackState(draft: CacheState, fallback: CacheState): void {
  for (const [key, row] of fallback.snapshots) {
    const current = draft.snapshots.get(key)
    if (!current || row.snapshot.fetchedAt >= current.snapshot.fetchedAt) {
      draft.snapshots.set(key, row)
    }
  }

  for (const [key, row] of fallback.browse) {
    const current = draft.browse.get(key)
    if (!current || row.value.visitedAt >= current.value.visitedAt) {
      draft.browse.set(key, row)
    }
  }
}

function writeCacheState(transaction: IDBTransaction, draft: CacheState): void {
  const snapshots = transaction.objectStore('programmeCache')
  snapshots.clear()
  for (const [key, value] of draft.snapshots) {
    snapshots.put(value, key)
  }

  const browse = transaction.objectStore('browseState')
  browse.clear()
  for (const [key, value] of draft.browse) {
    browse.put(value, key)
  }

  transaction.objectStore('meta').put(draft.epoch, 'cacheEpoch')
}

export function createWebProgrammeCache(database: ApplicationDatabase): {
  port: ProgrammeCachePort
  dispose(): void
} {
  let state: CacheState = { epoch: crypto.randomUUID(), snapshots: new Map(), browse: new Map() }
  let fallback: CacheState | null = null
  let epochLoaded = false
  let disposed = false
  let queue: Promise<unknown> = Promise.resolve()
  let clock = 0
  const listeners = new Set<(epoch: string) => void>()
  const channel =
    typeof BroadcastChannel === 'undefined' ? null : new BroadcastChannel('sctv-dl:programme-cache')

  function notify(epoch: string): void {
    if (disposed) {
      return
    }

    for (const listener of listeners) {
      listener(epoch)
    }
  }

  function access(): number {
    clock = Math.max(clock + 1, Date.now())

    return clock
  }

  function trim(draft: CacheState): void {
    const entries = [...draft.snapshots.entries()].sort((a, b) => a[1].accessed - b[1].accessed)
    let bytes = entries.reduce((total, [, row]) => total + snapshotBytes(row.snapshot), 0)
    while (draft.snapshots.size > MAX_CACHE_SNAPSHOTS || bytes > MAX_CACHE_BYTES) {
      const row = entries.shift()
      if (!row) {
        break
      }

      draft.snapshots.delete(row[0])
      bytes -= snapshotBytes(row[1].snapshot)
    }

    const browse = [...draft.browse.entries()].sort((a, b) =>
      b[1].value.visitedAt.localeCompare(a[1].value.visitedAt),
    )
    for (const [key] of browse.slice(MAX_BROWSE_STATES)) {
      draft.browse.delete(key)
    }
  }

  // The epoch and all changes are checked inside one read-write transaction.
  // Other tabs cannot insert a clear between validation and storage commitment.
  async function transact<T>(action: (draft: CacheState) => T): Promise<T> {
    const connection = await database.open()

    return new Promise<T>((resolve, reject) => {
      const previousEpoch = state.epoch
      const tx = connection.transaction(['programmeCache', 'browseState', 'meta'], 'readwrite')
      const snapshots = tx.objectStore('programmeCache').getAll()
      const browse = tx.objectStore('browseState').getAll()
      const epoch = tx.objectStore('meta').get('cacheEpoch')
      let result: T
      let draft: CacheState
      let cause: unknown
      tx.onabort = () => reject(cause ?? tx.error ?? new Error('Cache transaction aborted'))
      tx.onerror = () => {
        /* Abort reports the rolled-back operation. */
      }

      tx.oncomplete = () => {
        state = draft
        fallback = null
        if (epochLoaded && previousEpoch !== state.epoch) {
          notify(state.epoch)
        }

        epochLoaded = true

        resolve(result)
      }

      epoch.onsuccess = () => {
        try {
          draft = decodeCacheState(epoch.result, snapshots.result, browse.result, state.epoch)

          // Retry memory-only writes after quota/permission failures, but only
          // within their captured epoch. A durable clear discards every fallback.
          if (fallback?.epoch === draft.epoch) {
            mergeFallbackState(draft, fallback)
          } else {
            fallback = null
          }

          // Preserve the committed state if a quota error aborts the mutation.
          state = structuredClone(draft)
          result = action(draft)
          trim(draft)
          writeCacheState(tx, draft)
        } catch (error) {
          cause = error
          tx.abort()
        }
      }
    })
  }

  function enqueue<T>(action: () => Promise<T>): Promise<T> {
    const result = queue.then(() => {
      if (disposed) {
        throw new Error('Programme cache disposed')
      }

      return action()
    })
    queue = result.catch(() => {})

    return result
  }

  async function perform<T>(
    action: (draft: CacheState) => T,
  ): Promise<{ result: T; persisted: boolean; warning: string | null }> {
    try {
      return { result: await transact(action), persisted: true, warning: null }
    } catch {
      const result = action(state)
      trim(state)
      fallback = structuredClone(state)
      epochLoaded = true

      return { result, persisted: false, warning: storageWarning }
    }
  }

  const port: ProgrammeCachePort = {
    read(key) {
      const name = programmeCacheKey(key)

      return enqueue(async () => {
        const { result, ...status } = await perform((draft) => {
          const row = draft.snapshots.get(name)
          if (row) {
            row.accessed = access()
          }

          return { epoch: draft.epoch, snapshot: row?.snapshot ?? null }
        })

        return { ...result, ...status }
      })
    },
    write(input, expectedEpoch) {
      const payload = programmeCachePayloadSchema.parse(input)
      const name = programmeCacheKey(payload)

      return enqueue(async () => {
        let oversized = false
        const { result, ...status } = await perform((draft) => {
          const previous = draft.snapshots.get(name)?.snapshot ?? null
          if (draft.epoch !== expectedEpoch) {
            return { epoch: draft.epoch, snapshot: previous, accepted: false }
          }

          const snapshot: ProgrammeSnapshot = {
            ...payload,
            version: 1,
            revision:
              previous && sameProgrammePayload(previous, payload)
                ? previous.revision
                : crypto.randomUUID(),
            fetchedAt: new Date().toISOString(),
          }
          oversized = snapshotBytes(snapshot) > MAX_CACHE_BYTES
          if (!oversized) {
            draft.snapshots.set(name, { epoch: draft.epoch, snapshot, accessed: access() })
          }

          return { epoch: draft.epoch, snapshot, accepted: true }
        })

        return {
          ...result,
          ...status,
          ...(oversized ? { persisted: false, warning: oversizedWarning } : {}),
        }
      })
    },
    readBrowseState(programmeId) {
      idSchema.parse(programmeId)

      return enqueue(async () => {
        const { result, ...status } = await perform((draft) => ({
          epoch: draft.epoch,
          value: draft.browse.get(programmeId)?.value ?? null,
        }))

        return { ...result, ...status }
      })
    },
    writeBrowseState(input, expectedEpoch) {
      const value: ArchiveBrowseState = archiveBrowseStateSchema.parse(input)

      return enqueue(async () => {
        const { result: accepted, persisted } = await perform((draft) => {
          if (draft.epoch !== expectedEpoch) {
            return false
          }

          draft.browse.set(value.programmeId, { epoch: draft.epoch, value })

          return true
        })

        return { accepted, persisted }
      })
    },
    clear() {
      return enqueue(async () => {
        const connection = await database.open()
        const epoch = crypto.randomUUID()
        // Commit the fence before cleanup. A later cleanup failure must not make
        // pre-clear responses eligible to write again.
        await new Promise<void>((resolve, reject) => {
          const tx = connection.transaction('meta', 'readwrite')
          tx.objectStore('meta').put(epoch, 'cacheEpoch')
          tx.oncomplete = () => resolve()
          tx.onabort = () => reject(tx.error ?? new Error('无法清除节目缓存，请重试'))
        })
        state = { epoch, snapshots: new Map(), browse: new Map() }
        fallback = null
        epochLoaded = true
        notify(epoch)
        channel?.postMessage(epoch)
        // transact loads only the current durable generation, preserving writes
        // that another tab committed after the clear fence.
        await transact(() => {})

        return { epoch }
      })
    },
    async subscribeCleared(listener) {
      if (disposed) {
        throw new Error('Programme cache disposed')
      }

      listeners.add(listener)

      return () => {
        listeners.delete(listener)
      }
    },
  }

  if (channel) {
    channel.onmessage = (event: MessageEvent<unknown>) => {
      if (typeof event.data === 'string' && event.data !== state.epoch) {
        // Broadcast delivery may be reordered; the database owns the latest fence.
        void enqueue(async () => {
          await transact(() => {})
        }).catch(() => {})
      }
    }
  }

  return {
    port,
    dispose() {
      disposed = true
      listeners.clear()
      channel?.close()
    },
  }
}
