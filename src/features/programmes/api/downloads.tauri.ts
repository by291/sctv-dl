import { Channel, invoke } from '@tauri-apps/api/core'
import { z } from 'zod'

import {
  downloadRequestSchema,
  downloadSnapshotSchema,
  downloadEventSchema,
  downloadActionRequestSchema,
  downloadActionResultSchema,
  fileFailureSchema,
} from '@shared/contracts/downloads'

import { playbackSessionSchema } from '@shared/contracts/media'
import { invokeAbortable } from '@/shared/platform/invoke-abortable.tauri'
import { invokeValidated } from '@/shared/platform/invoke-validated.tauri'

import type { NativeDownloadPort } from '@/shared/platform/ports'

const startSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('cancelled') }),
  z.object({
    kind: z.literal('native'),
    taskIds: z.array(z.string().min(1)),
    usedFallback: z.boolean(),
    failures: z.array(fileFailureSchema),
  }),
])

async function request<T>(
  command: string,
  args: Record<string, unknown>,
  schema: z.ZodType<T>,
): Promise<T> {
  return invokeValidated(command, args, schema, {
    failure: '无法调用桌面下载服务，请重试',
    invalid: '桌面下载服务数据格式异常，请检查客户端版本',
  })
}

export function createTauriDownloads(): NativeDownloadPort {
  return {
    kind: 'native',
    snapshot: () => request('get_download_snapshot', {}, downloadSnapshotSchema),
    act: (input) =>
      request(
        'act_on_download',
        { request: downloadActionRequestSchema.parse(input) },
        downloadActionResultSchema,
      ),
    openPlayback: (taskId, signal) =>
      invokeAbortable(
        'open_local_playback',
        { taskId: z.string().min(1).parse(taskId) },
        playbackSessionSchema,
        signal,
        (raw) => {
          if (raw && typeof raw === 'object' && 'id' in raw && typeof raw.id === 'string') {
            void invoke('close_playback', { sessionId: raw.id }).catch(() => {})
          }
        },
      ),
    async subscribeEvents(listener) {
      let active = true
      const onEvent = new Channel<unknown>()
      onEvent.onmessage = (raw) => {
        const event = downloadEventSchema.safeParse(raw)
        if (active && event.success) {
          listener(event.data)
        }
      }

      let subscriptionId: string
      try {
        subscriptionId = await request('subscribe_download_events', { onEvent }, z.string().min(1))
      } catch (cause) {
        active = false
        throw cause
      }

      return () => {
        if (!active) {
          return
        }

        active = false
        void invoke('unsubscribe_download_events', { subscriptionId }).catch(() => {})
      }
    },
    start: (input) =>
      request('start_downloads', { request: downloadRequestSchema.parse(input) }, startSchema),
    getDirectory: () => request('get_download_directory', {}, z.string().nullable()),
    chooseDirectory: () => request('choose_download_directory', {}, z.string().nullable()),
  }
}
