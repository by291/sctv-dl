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

export function createTauriProgrammeCache(): { port: ProgrammeCachePort; dispose(): void } {
  let disposed = false
  const listeners = new Set<(epoch: string) => void>()

  async function request<T>(
    command: string,
    args: Record<string, unknown>,
    schema: z.ZodType<T>,
  ): Promise<T> {
    if (disposed) {
      throw new Error('Programme cache disposed')
    }

    return invokeValidated(command, args, schema, {
      failure: '无法访问节目缓存，请重试',
      invalid: '节目缓存数据格式异常，请检查客户端版本',
    })
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
    async clear() {
      try {
        const result = await request(
          'clear_programme_cache',
          {},
          z.object({ epoch: z.string().min(1) }),
        )
        if (!disposed) {
          for (const listener of listeners) {
            listener(result.epoch)
          }
        }

        return result
      } catch (error) {
        // Cleanup can fail after the durable fence was committed. Read the fence
        // back so mounted owners still invalidate work from the old generation.
        try {
          const current = await port.read({ kind: 'catalogue' })
          if (!disposed) {
            for (const listener of listeners) {
              listener(current.epoch)
            }
          }
        } catch {
          /* Preserve the actionable clear error if storage is unavailable. */
        }

        throw error
      }
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
