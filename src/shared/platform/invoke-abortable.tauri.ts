import { invoke } from '@tauri-apps/api/core'
import { applicationErrorSchema } from '@shared/contracts/errors'
import type { z } from 'zod'

function nativeError(value: unknown): Error {
  const parsed = applicationErrorSchema.safeParse(value)
  if (parsed.success) {
    return parsed.data.code === 'cancelled'
      ? new DOMException(parsed.data.message, 'AbortError')
      : new Error(parsed.data.message)
  }

  return new Error('无法调用桌面服务，请重启应用后重试')
}

export async function invokeAbortable<T>(
  command: string,
  args: Record<string, unknown>,
  schema: z.ZodType<T>,
  signal?: AbortSignal,
  onLate?: (raw: unknown) => void,
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
          onLate?.(raw)

          return
        }

        const result = schema.safeParse(raw)
        if (!result.success) {
          onLate?.(raw)
        }

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
