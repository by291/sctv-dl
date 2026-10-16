import { invoke } from '@tauri-apps/api/core'

import { playbackRequestSchema, playbackSessionSchema } from '@shared/contracts/media'
import { invokeAbortable } from '@/shared/platform/invoke-abortable.tauri'

import type { PlaybackPort } from '@/shared/platform/ports'

export function createTauriPlayback(): PlaybackPort & { dispose(): Promise<void> } {
  const sessions = new Set<string>()
  const pending = new Set<AbortController>()
  let disposed = false

  async function close(id: string) {
    sessions.delete(id)
    await invoke('close_playback', { sessionId: id })
  }

  function closeLate(raw: unknown) {
    if (raw && typeof raw === 'object' && 'id' in raw && typeof raw.id === 'string') {
      void close(raw.id).catch(() => {})
    }
  }

  return {
    async open(input, signal) {
      signal?.throwIfAborted()
      if (disposed) {
        throw new DOMException('视频服务已关闭', 'AbortError')
      }

      const request = playbackRequestSchema.parse(input)
      const controller = new AbortController()
      const abort = () => controller.abort(signal?.reason)
      signal?.addEventListener('abort', abort, { once: true })
      pending.add(controller)
      try {
        const session = await invokeAbortable(
          'open_playback',
          { request },
          playbackSessionSchema,
          controller.signal,
          closeLate,
        )
        if (disposed || controller.signal.aborted) {
          await close(session.id)
          throw new DOMException('请求已取消', 'AbortError')
        }

        sessions.add(session.id)

        return session
      } finally {
        pending.delete(controller)
        signal?.removeEventListener('abort', abort)
      }
    },
    close,
    async dispose() {
      disposed = true
      for (const controller of pending) {
        controller.abort()
      }

      await Promise.allSettled([...sessions].map(close))
    },
  }
}
