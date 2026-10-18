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

import type { HistoryPort } from '@/shared/platform/ports'

export function createTauriHistory(): { port: HistoryPort; dispose(): Promise<void> } {
  let disposed = false
  let writeRevision = 0
  let queue: Promise<unknown> = Promise.resolve()
  const subscriptions = new Set<() => Promise<void>>()
  const failedWrites = new Map<string, unknown>()

  async function request<T>(
    command: string,
    args: Record<string, unknown>,
    schema: z.ZodType<T>,
  ): Promise<T> {
    if (disposed) {
      throw new Error('History disposed')
    }

    return invokeValidated(command, args, schema, {
      failure: '无法访问观看历史，请重试',
      invalid: '观看历史数据格式异常，请检查客户端版本',
    })
  }

  function mutate<T>(
    command: string,
    args: Record<string, unknown>,
    schema: z.ZodType<T>,
  ): Promise<T> {
    writeRevision += 1
    const key = `${command}:${JSON.stringify(args.sessionId ?? args.content ?? '')}`
    const pending = queue.then(async () => {
      try {
        const result = await request(command, args, schema)
        failedWrites.delete(key)

        return result
      } catch (cause) {
        failedWrites.set(key, cause)
        throw cause
      }
    })
    queue = pending.catch(() => {})

    return pending
  }

  const port: HistoryPort = {
    list: () => request('list_history', {}, historySnapshotSchema),
    begin: (metadata) =>
      mutate(
        'begin_history',
        { metadata: historyMetadataSchema.parse(metadata) },
        historySessionSchema,
      ),
    record: (sessionId, sample) =>
      mutate(
        'record_history',
        { sessionId, sample: historySampleSchema.parse(sample) },
        z.object({ accepted: z.boolean(), persisted: z.boolean() }),
      ),
    end: async (sessionId) => {
      await mutate('end_history', { sessionId }, z.null())
    },
    remove: async (content) => {
      await mutate('remove_history', { content: contentRefSchema.parse(content) }, z.null())
    },
    clear: async () => {
      await mutate('clear_history', {}, z.null())
    },
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

      if (failedWrites.size) {
        throw new Error('观看历史有未保存的更改，请重试', {
          cause: failedWrites.values().next().value,
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
