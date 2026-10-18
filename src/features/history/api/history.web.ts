import { z } from 'zod'
import {
  historyEntrySchema,
  historyKey,
  historyMetadataSchema,
  historySampleSchema,
  isHistoryCompleted,
} from '@shared/contracts/history'

import type { HistoryEntry, HistoryMetadata, HistorySnapshot } from '@shared/contracts/history'
import type { ApplicationDatabase } from '@/shared/storage/application-database.web'
import type { HistoryPort } from '@/shared/platform/ports'

const sessionSchema = z.object({
  id: z.string(),
  metadata: historyMetadataSchema,
  sequence: z.number().int().nonnegative(),
})
type Session = z.infer<typeof sessionSchema>
interface State {
  entries: HistoryEntry[]
  sessions: Session[]
  revision: number
}

export function createWebHistory(database: ApplicationDatabase): {
  port: HistoryPort
  dispose(): void
} {
  let state: State = { entries: [], sessions: [], revision: 0 }
  let warning: string | null = null
  let disposed = false
  let writeRevision = 0
  let queue: Promise<unknown> = Promise.resolve()
  const pendingMutations: Array<(draft: State) => unknown> = []
  const listeners = new Set<(snapshot: HistorySnapshot) => void>()
  const channel =
    typeof BroadcastChannel === 'undefined' ? null : new BroadcastChannel('sctv-dl:history')

  function snapshot(): HistorySnapshot {
    return structuredClone({
      entries: state.entries,
      revision: state.revision,
      persisted: warning === null,
      warning,
    })
  }

  function notify(): void {
    if (disposed) {
      return
    }

    for (const listener of listeners) {
      listener(snapshot())
    }
  }

  // Check session ownership in the write transaction, so another tab's clear
  // cannot race a read followed by an independent write and resurrect progress.
  async function transact<T>(mutate: boolean, action: (draft: State) => T): Promise<T> {
    const connection = await database.open()
    const recovering = pendingMutations.length > 0
    const writes = mutate || recovering

    return new Promise<T>((resolve, reject) => {
      const transaction = connection.transaction(
        ['history', 'historySessions', 'meta'],
        writes ? 'readwrite' : 'readonly',
      )
      const entries = transaction.objectStore('history').getAll()
      const sessions = transaction.objectStore('historySessions').getAll()
      const revision = transaction.objectStore('meta').get('historyRevision')
      let result: T
      let next: State
      let cause: unknown

      transaction.onabort = () =>
        reject(cause ?? transaction.error ?? new Error('History transaction aborted'))
      transaction.onerror = () => {
        /* onabort rejects after rollback. */
      }

      transaction.oncomplete = () => {
        state = next
        pendingMutations.length = 0
        warning = null
        resolve(result)
      }

      revision.onsuccess = () => {
        try {
          next = {
            entries: z
              .array(historyEntrySchema)
              .max(500)
              .parse(entries.result)
              .sort((left, right) => right.viewedAt.localeCompare(left.viewedAt)),
            sessions: z.array(sessionSchema).parse(sessions.result),
            revision: z
              .number()
              .int()
              .nonnegative()
              .parse(revision.result ?? 0),
          }
          // Replay operations against fresh durable ownership, never copy the
          // fallback snapshot over other tabs' commits. Removed/replaced tokens
          // make their pending progress harmless no-ops.
          for (const pending of pendingMutations) {
            pending(next)
          }

          next.revision = Math.max(next.revision, state.revision)
          // Fresh ownership remains authoritative even if quota prevents this
          // transaction from committing. Keep replayed local progress only for
          // still-current tokens, and preserve the observable revision floor.
          state = structuredClone(next)
          result = action(next)
          if (!writes) {
            return
          }

          transaction.objectStore('history').clear()
          for (const entry of next.entries) {
            transaction.objectStore('history').put(entry, historyKey(entry.content))
          }

          transaction.objectStore('historySessions').clear()
          for (const session of next.sessions) {
            transaction
              .objectStore('historySessions')
              .put(session, historyKey(session.metadata.content))
          }

          transaction.objectStore('meta').put(next.revision, 'historyRevision')
        } catch (error) {
          cause = error
          transaction.abort()
        }
      }
    })
  }

  function enqueue<T>(mutate: boolean, action: (draft: State) => T): Promise<T> {
    if (mutate) {
      writeRevision += 1
    }

    const pending = queue.then(async () => {
      if (disposed) {
        throw new Error('History disposed')
      }

      let result: T
      const recovering = warning !== null
      try {
        result = await transact(mutate, action)
      } catch {
        warning = '观看历史无法保存到本地，当前记录仅在本次会话中保留'
        result = action(state)
        if (mutate) {
          pendingMutations.push(action)
        }
      }

      notify()
      if ((mutate || recovering) && warning === null) {
        channel?.postMessage(null)
      }

      return result
    })
    queue = pending.catch(() => {})

    return pending
  }

  const port: HistoryPort = {
    async list() {
      await enqueue(false, () => {})

      return snapshot()
    },
    begin(input) {
      const metadata: HistoryMetadata = historyMetadataSchema.parse(input)
      if (new TextEncoder().encode(JSON.stringify(metadata)).length > 16384) {
        return Promise.reject(new Error('History metadata too large'))
      }

      const id = crypto.randomUUID()
      let expected: { revision: number; sessionId: string | undefined } | undefined

      return enqueue(true, (draft) => {
        const key = historyKey(metadata.content)
        const entry = draft.entries.find((value) => historyKey(value.content) === key) ?? null
        const existing = draft.sessions.find((value) => historyKey(value.metadata.content) === key)
        // A delayed begin must not take ownership from a newer tab or reopen
        // content deleted while this tab was using session-only storage.
        expected ??= { revision: draft.revision, sessionId: existing?.id }
        if (draft.revision !== expected.revision || existing?.id !== expected.sessionId) {
          return { id, entry: structuredClone(entry) }
        }

        draft.sessions = draft.sessions.filter(
          (value) => historyKey(value.metadata.content) !== key,
        )
        draft.sessions.push({ id, metadata, sequence: 0 })
        // Session ownership changes must remain observable after end removes the
        // token, otherwise a delayed fallback begin could install an older owner.
        draft.revision += 1

        return { id, entry: structuredClone(entry) }
      })
    },
    async record(id, input) {
      const sample = historySampleSchema.parse(input)
      const accepted = await enqueue(true, (draft) => {
        const session = draft.sessions.find((value) => value.id === id)
        if (!session || sample.sequence <= session.sequence) {
          return false
        }

        session.sequence = sample.sequence
        const key = historyKey(session.metadata.content)
        draft.entries = draft.entries.filter((entry) => historyKey(entry.content) !== key)
        // Monotonic timestamps disambiguate records saved in the same millisecond.
        const previous = draft.entries[0]?.viewedAt
        const viewedAt = new Date(
          Math.max(Date.now(), previous ? Date.parse(previous) + 1 : 0),
        ).toISOString()
        draft.entries.unshift({
          ...session.metadata,
          positionMs: sample.positionMs,
          durationMs: sample.durationMs,
          viewedAt,
          completed: isHistoryCompleted(sample),
        })
        draft.entries = draft.entries.slice(0, 500)
        draft.revision += 1

        return true
      })

      return { accepted, persisted: warning === null }
    },
    end(id) {
      return enqueue(true, (draft) => {
        draft.sessions = draft.sessions.filter((value) => value.id !== id)
      })
    },
    remove(content) {
      return enqueue(true, (draft) => {
        const key = historyKey(content)
        draft.entries = draft.entries.filter((entry) => historyKey(entry.content) !== key)
        draft.sessions = draft.sessions.filter(
          (session) => historyKey(session.metadata.content) !== key,
        )
        draft.revision += 1
      })
    },
    clear() {
      return enqueue(true, (draft) => {
        draft.entries = []
        draft.sessions = []
        draft.revision += 1
      })
    },
    async subscribe(listener) {
      listeners.add(listener)
      try {
        await port.list()
      } catch (error) {
        listeners.delete(listener)
        throw error
      }

      return () => {
        listeners.delete(listener)
      }
    },
    async flush() {
      if (warning !== null) {
        await enqueue(false, () => {})
      }

      let pending: Promise<unknown>
      do {
        pending = queue
        await pending
      } while (queue !== pending)

      if (warning !== null) {
        throw new Error(warning)
      }
    },
    getWriteRevision: () => writeRevision,
  }

  function refresh(): void {
    void port.list().catch(() => {})
  }

  function visibility(): void {
    if (document.visibilityState === 'visible') {
      refresh()
    }
  }

  if (channel) {
    channel.onmessage = refresh
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', visibility)
  }

  return {
    port,
    dispose() {
      disposed = true
      listeners.clear()
      channel?.close()
      if (typeof document !== 'undefined') {
        document.removeEventListener('visibilitychange', visibility)
      }
    },
  }
}
