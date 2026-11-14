import { z } from 'zod'
import {
  archiveBrowseStateSchema,
  browseStateReadSchema,
  cacheReadSchema,
  cacheWriteResultSchema,
  programmeCacheKeySchema,
  programmeCachePayloadSchema,
} from '@shared/contracts/programme-cache'
import { idSchema } from '@shared/contracts/programmes'
import { invokeValidated } from '@/shared/platform/invoke-validated.tauri'

import type { ProgrammeCachePort } from '@/shared/platform/ports'

const clearResultSchema = z.object({ epoch: z.string().min(1) })

// Expose the native cache and notify owners when its epoch changes.
export function createTauriProgrammeCache(): { port: ProgrammeCachePort; dispose(): void } {
  let disposed = false
  let clearing: Promise<unknown> = Promise.resolve()
  const listeners = new Set<(epoch: string) => void>()

  async function request<T>(
    command: string,
    args: Record<string, unknown>,
    schema: z.ZodType<T>,
  ): Promise<T> {
    if (disposed) {
      throw new Error('Programme cache disposed')
    }

    return invokeValidated({
      command,
      parameters: args,
      schema,
      messages: {
        failure: '无法访问节目缓存，请重试',
        invalid: '节目缓存数据格式异常，请检查客户端版本',
      },
    })
  }

  function notifyCleared(epoch: string): void {
    if (disposed) {
      return
    }

    for (const listener of listeners) {
      listener(epoch)
    }
  }

  async function readEpoch(): Promise<string | undefined> {
    try {
      return (await port.read({ kind: 'catalogue' })).epoch
    } catch {
      // Clear can still succeed when its preliminary read fails.
      return undefined
    }
  }

  async function clearGeneration() {
    const previousEpoch = await readEpoch()
    let result: z.infer<typeof clearResultSchema>

    try {
      result = await request('clear_programme_cache', {}, clearResultSchema)
    } catch (error) {
      // Post-commit cleanup can fail after the fence changed. An unchanged fence
      // leaves mounted owners and their in-flight work valid.
      const currentEpoch = await readEpoch()
      if (previousEpoch && currentEpoch && previousEpoch !== currentEpoch) {
        notifyCleared(currentEpoch)
      }

      throw error
    }

    notifyCleared(result.epoch)

    return result
  }

  const port: ProgrammeCachePort = {
    read: (key) =>
      request('read_programme_cache', { key: programmeCacheKeySchema.parse(key) }, cacheReadSchema),
    write: (payload, expectedEpoch) =>
      request(
        'write_programme_cache',
        { payload: programmeCachePayloadSchema.parse(payload), expectedEpoch },
        cacheWriteResultSchema,
      ),
    readBrowseState: (programmeId) =>
      request(
        'read_archive_browse_state',
        { programmeId: idSchema.parse(programmeId) },
        browseStateReadSchema,
      ),
    writeBrowseState: (value, expectedEpoch) =>
      request(
        'write_archive_browse_state',
        { value: archiveBrowseStateSchema.parse(value), expectedEpoch },
        z.object({ accepted: z.boolean(), persisted: z.boolean() }),
      ),
    clear() {
      // Serialize clear attempts so each recovery read describes its own fence.
      const pending = clearing.then(clearGeneration)
      clearing = pending.catch(() => {})

      return pending
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

  return {
    port,
    dispose() {
      disposed = true
      listeners.clear()
    },
  }
}
