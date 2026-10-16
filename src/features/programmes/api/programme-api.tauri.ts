import { invoke } from '@tauri-apps/api/core'
import { z } from 'zod'

import { applicationErrorSchema } from '@shared/contracts/errors'
import {
  idSchema,
  programmeSchema,
  programmeDateSchema,
  programmeContentSchema,
} from '@shared/contracts/programmes'

import type { ProgrammeApi } from '@/shared/platform/ports'

function nativeError(value: unknown): Error {
  const parsed = applicationErrorSchema.safeParse(value)
  if (parsed.success) {
    return parsed.data.code === 'cancelled'
      ? new DOMException(parsed.data.message, 'AbortError')
      : new Error(parsed.data.message)
  }

  return new Error('无法调用桌面服务，请重启应用后重试')
}

async function request<T>(
  command: string,
  args: Record<string, string>,
  schema: z.ZodType<T>,
  signal?: AbortSignal,
): Promise<T> {
  signal?.throwIfAborted()
  const requestId = crypto.randomUUID()

  return new Promise<T>((resolve, reject) => {
    let finished = false
    const settle = (action: () => void) => {
      if (finished) {
        return
      }

      finished = true
      signal?.removeEventListener('abort', abort)
      action()
    }

    const abort = () => {
      settle(() => reject(signal?.reason ?? new DOMException('请求已取消', 'AbortError')))
      void invoke('cancel_request', { requestId }).catch(() => {})
    }

    signal?.addEventListener('abort', abort, { once: true })
    void invoke<unknown>(command, { ...args, requestId }).then(
      (raw) => {
        if (finished) {
          return
        }

        const result = schema.safeParse(raw)
        settle(() =>
          result.success
            ? resolve(result.data)
            : reject(new Error('桌面服务数据格式异常，请检查客户端版本')),
        )
      },
      (error: unknown) => settle(() => reject(nativeError(error))),
    )
  })
}

function validatedId(value: string): string {
  const result = idSchema.safeParse(value)
  if (!result.success) {
    throw new Error('节目 ID 无效')
  }

  return result.data
}

export function createTauriProgrammeApi(): ProgrammeApi {
  return {
    programmes: (signal) => request('list_programmes', {}, z.array(programmeSchema), signal),
    async dates(programmeId, signal) {
      return request(
        'list_programme_dates',
        { programmeId: validatedId(programmeId) },
        z.array(programmeDateSchema),
        signal,
      )
    },
    async contents(programmeId, dateId, signal) {
      return request(
        'list_programme_contents',
        { programmeId: validatedId(programmeId), dateId: validatedId(dateId) },
        z.array(programmeContentSchema),
        signal,
      )
    },
  }
}
