import { invoke } from '@tauri-apps/api/core'
import { z } from 'zod'

import { playbackRequestSchema, playbackSessionSchema } from '@shared/contracts/media'
import { startAbortableInvocation } from '@/shared/platform/invoke-abortable.tauri'

import type { PlaybackPort } from '@/shared/platform/ports'
import type { PlaybackSession } from '@shared/contracts/media'

interface OpenPlaybackOptions {
  command: 'open_playback' | 'open_local_playback'
  parameters: Record<string, unknown>
  signal?: AbortSignal
}

// Own local and online playback from IPC admission through confirmed session closure.
export function createTauriPlayback(): PlaybackPort & {
  openLocal(taskId: string, signal?: AbortSignal): Promise<PlaybackSession>
  dispose(): Promise<void>
} {
  const sessions = new Set<string>()
  const closing = new Map<string, Promise<void>>()
  const pending = new Map<AbortController, Promise<void>>()
  let isDisposed = false
  let disposal: Promise<void> | undefined

  function close(id: string): Promise<void> {
    const previous = closing.get(id)
    if (previous) {
      return previous
    }

    // A rejected close retains ownership so disposal can try the idempotent command again.
    sessions.add(id)
    const completion = (async () => {
      await invoke('close_playback', { sessionId: id })
      sessions.delete(id)
    })().finally(() => {
      closing.delete(id)
    })
    closing.set(id, completion)

    return completion
  }

  async function releaseReply(raw: unknown) {
    // A malformed reply may still identify a session that the native service created.
    if (raw && typeof raw === 'object' && 'id' in raw && typeof raw.id === 'string') {
      await close(raw.id)
    }
  }

  async function openSession({ command, parameters, signal }: OpenPlaybackOptions) {
    signal?.throwIfAborted()
    if (isDisposed) {
      throw new DOMException('视频服务已关闭', 'AbortError')
    }

    const controller = new AbortController()
    const abort = () => controller.abort(signal?.reason)
    signal?.addEventListener('abort', abort, { once: true })

    const invocation = startAbortableInvocation({
      command,
      parameters,
      schema: playbackSessionSchema,
      signal: controller.signal,
      releaseReply,
    })
    const result = invocation.result.then(async (session) => {
      if (controller.signal.aborted) {
        await close(session.id).catch((cause: unknown) => {
          console.error('Failed to close an aborted playback session', cause)
        })
        controller.signal.throwIfAborted()
      }

      sessions.add(session.id)

      return session
    })

    // The caller can stop waiting on abort while disposal still awaits IPC and its cleanup.
    const completed = Promise.allSettled([invocation.completion, result]).then(() => {
      pending.delete(controller)
    })
    pending.set(controller, completed)

    try {
      return await result
    } finally {
      signal?.removeEventListener('abort', abort)
    }
  }

  async function releaseSessions() {
    for (const controller of pending.keys()) {
      controller.abort()
    }

    await Promise.all(pending.values())
    await Promise.allSettled(closing.values())

    const results = await Promise.allSettled([...sessions].map(close))
    const errors = results.flatMap((result) =>
      result.status === 'rejected' ? [result.reason] : [],
    )
    if (errors.length > 0) {
      throw new AggregateError(errors, 'Failed to close native playback sessions')
    }
  }

  return {
    async open(input, signal) {
      signal?.throwIfAborted()
      const request = playbackRequestSchema.parse(input)

      return openSession({ command: 'open_playback', parameters: { request }, signal })
    },
    async openLocal(value, signal) {
      signal?.throwIfAborted()
      const taskId = z.string().min(1).parse(value)

      return openSession({ command: 'open_local_playback', parameters: { taskId }, signal })
    },
    close,
    dispose() {
      isDisposed = true
      disposal ??= releaseSessions().catch((cause: unknown) => {
        // The same owner can retry failed releases without reopening admission.
        disposal = undefined
        throw cause
      })

      return disposal
    },
  }
}
