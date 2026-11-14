import { Channel, invoke } from '@tauri-apps/api/core'
import { z } from 'zod'
import {
  historyMetadataSchema,
  historySampleSchema,
  historySessionSchema,
  historySnapshotSchema,
} from '@shared/contracts/history'
import { contentRefSchema } from '@shared/contracts/programmes'
import { invokeValidated } from '@/shared/platform/invoke-validated.tauri'

import type { ContentRef } from '@shared/contracts/programmes'
import type { HistoryPort } from '@/shared/platform/ports'

const recordResultSchema = z.object({ accepted: z.boolean(), persisted: z.boolean() })

interface SampleFailure {
  sequence: number
  cause: unknown
}

function historyContentKey(content: ContentRef): string {
  return [content.programmeId, content.dateId, content.contentId].join(':')
}

// Expose native history, serialize writes, and track persistence failures.
export function createTauriHistory(): { port: HistoryPort; dispose(): Promise<void> } {
  let disposed = false
  let writeRevision = 0
  let queue: Promise<unknown> = Promise.resolve()
  const subscriptions = new Set<() => Promise<void>>()
  const contentBySession = new Map<string, string>()
  const failedSamples = new Map<string, SampleFailure & { sessionId: string }>()
  const failedRemovals = new Map<string, { cause: unknown }>()
  let failedClear: { cause: unknown } | undefined

  async function request<T>(
    command: string,
    args: Record<string, unknown>,
    schema: z.ZodType<T>,
  ): Promise<T> {
    if (disposed) {
      throw new Error('History disposed')
    }

    return invokeValidated({
      command,
      parameters: args,
      schema,
      messages: {
        failure: '无法访问观看历史，请重试',
        invalid: '观看历史数据格式异常，请检查客户端版本',
      },
    })
  }

  function enqueue<T>(operation: () => Promise<T>): Promise<T> {
    writeRevision += 1
    const pending = queue.then(operation)

    // Keep processing later writes while the caller receives this operation's failure.
    queue = pending.catch(() => {})

    return pending
  }

  const port: HistoryPort = {
    list: () => request('list_history', {}, historySnapshotSchema),
    begin: (input) => {
      const metadata = historyMetadataSchema.parse(input)

      return enqueue(async () => {
        const session = await request('begin_history', { metadata }, historySessionSchema)
        contentBySession.set(session.id, historyContentKey(metadata.content))

        return session
      })
    },
    record: (sessionId, sample) =>
      enqueue(async () => {
        const contentKey = contentBySession.get(sessionId) ?? `session:${sessionId}`
        const parameters = { sessionId, sample: historySampleSchema.parse(sample) }

        try {
          const result = await request('record_history', parameters, recordResultSchema)
          const failure = failedSamples.get(contentKey)
          // Native can confirm durability on a retry without accepting the sample again.
          const isRetry = failure?.sessionId === sessionId && sample.sequence >= failure.sequence
          if (result.persisted && (result.accepted || isRetry)) {
            failedSamples.delete(contentKey)
          }

          return result
        } catch (cause) {
          failedSamples.set(contentKey, { sessionId, sequence: sample.sequence, cause })
          throw cause
        }
      }),
    end: (sessionId) =>
      enqueue(async () => {
        await request('end_history', { sessionId }, z.null())
        // Ending a token leaves its last failed sample unresolved until a later commit.
        contentBySession.delete(sessionId)
      }),
    remove: (input) => {
      const content = contentRefSchema.parse(input)
      const contentKey = historyContentKey(content)

      return enqueue(async () => {
        try {
          await request('remove_history', { content }, z.null())
          failedSamples.delete(contentKey)
          failedRemovals.delete(contentKey)
        } catch (cause) {
          failedRemovals.set(contentKey, { cause })
          throw cause
        }
      })
    },
    clear: () =>
      enqueue(async () => {
        try {
          await request('clear_history', {}, z.null())
          failedSamples.clear()
          failedRemovals.clear()
          failedClear = undefined
        } catch (cause) {
          failedClear = { cause }
          throw cause
        }
      }),
    async subscribe(listener) {
      let active = true
      const onEvent = new Channel<unknown>()
      onEvent.onmessage = (raw) => {
        const parsed = historySnapshotSchema.safeParse(raw)
        if (active && !disposed && parsed.success) {
          listener(parsed.data)
        }
      }

      const subscriptionId = await request('subscribe_history', { onEvent }, z.string().min(1))

      async function stop(): Promise<void> {
        if (!active) {
          return
        }

        active = false
        subscriptions.delete(stop)
        // Local callbacks stop synchronously; native channel teardown is best effort
        // if the process is already exiting. Disposal awaits attempted teardown.
        await invoke('unsubscribe_history', { subscriptionId }).catch(() => {})
      }

      if (disposed) {
        await stop()

        return () => {}
      }

      subscriptions.add(stop)

      return () => {
        void stop()
      }
    },
    async flush() {
      let pending: Promise<unknown>
      do {
        pending = queue
        await pending
      } while (queue !== pending)

      const failure =
        failedClear ?? failedRemovals.values().next().value ?? failedSamples.values().next().value
      if (failure) {
        throw new Error('观看历史有未保存的更改，请重试', {
          cause: failure.cause,
        })
      }

      const snapshot = await port.list()
      if (!snapshot.persisted) {
        throw new Error(snapshot.warning ?? '观看历史未保存')
      }
    },
    getWriteRevision: () => writeRevision,
  }

  return {
    port,
    async dispose() {
      await queue
      disposed = true
      await Promise.all([...subscriptions].map((stop) => stop()))
    },
  }
}
