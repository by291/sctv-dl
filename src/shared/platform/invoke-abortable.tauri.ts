import { invoke } from '@tauri-apps/api/core'
import { applicationErrorSchema } from '@shared/contracts/errors'
import type { z } from 'zod'

function nativeError(value: unknown): Error {
  const parsed = applicationErrorSchema.safeParse(value)
  if (parsed.success) {
    return parsed.data.code === 'cancelled'
      ? new DOMException(parsed.data.message, 'AbortError')
      : new Error(parsed.data.message, { cause: value })
  }

  return new Error('无法调用桌面服务，请重启应用后重试', { cause: value })
}

interface InvocationOptions<T> {
  command: string
  parameters: Record<string, unknown>
  schema: z.ZodType<T>
  signal?: AbortSignal
  releaseReply?: (raw: unknown) => Promise<void>
}

// Validate cancellable IPC for callers that do not own native resources in the reply.
export async function invokeAbortable<T>(options: InvocationOptions<T>): Promise<T> {
  return startAbortableInvocation(options).result
}

// Cancellation settles the request immediately; completion also waits for late reply cleanup.
export function startAbortableInvocation<T>({
  command,
  parameters,
  schema,
  signal,
  releaseReply,
}: InvocationOptions<T>): { result: Promise<T>; completion: Promise<void> } {
  signal?.throwIfAborted()
  const requestId = crypto.randomUUID()
  let resolve!: (value: T) => void
  let reject!: (cause: unknown) => void
  const result = new Promise<T>((accept, fail) => {
    resolve = accept
    reject = fail
  })
  let isSettled = false

  function settle(action: () => void) {
    if (isSettled) {
      return
    }

    isSettled = true
    signal?.removeEventListener('abort', abort)
    action()
  }

  function abort() {
    settle(() => reject(signal?.reason ?? new DOMException('请求已取消', 'AbortError')))

    // The native call may complete despite cancellation. Its completion still owns the reply.
    void cancelNativeRequest()
  }

  async function cancelNativeRequest() {
    try {
      await invoke('cancel_request', { requestId })
    } catch {
      // The command may already have settled or the bridge may have closed.
    }
  }

  async function discard(raw: unknown) {
    try {
      await releaseReply?.(raw)
    } catch (cause) {
      console.error('Failed to release a discarded native reply', cause)
    }
  }

  signal?.addEventListener('abort', abort, { once: true })
  const response = (async () => invoke<unknown>(command, { ...parameters, requestId }))()
  const completion = response.then(
    async (raw) => {
      if (isSettled) {
        await discard(raw)

        return
      }

      const parsed = schema.safeParse(raw)
      if (parsed.success) {
        settle(() => resolve(parsed.data))

        return
      }

      // A cleanup failure cannot replace the validation error seen by the requester.
      const error = new Error('桌面服务数据格式异常，请检查客户端版本', { cause: parsed.error })
      settle(() => reject(error))
      await discard(raw)
    },
    (error: unknown) => settle(() => reject(nativeError(error))),
  )

  return { result, completion }
}
