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
  return invokeValidated({
    command,
    parameters: args,
    schema,
    messages: {
      failure: '无法调用桌面下载服务，请重试',
      invalid: '桌面下载服务数据格式异常，请检查客户端版本',
    },
  })
}

// Expose native download commands and guarded event subscriptions.
export function createTauriDownloads(
  openPlayback: NativeDownloadPort['openPlayback'],
): NativeDownloadPort {
  return {
    kind: 'native',
    snapshot: () => request('get_download_snapshot', {}, downloadSnapshotSchema),
    act: (input) =>
      request(
        'act_on_download',
        { request: downloadActionRequestSchema.parse(input) },
        downloadActionResultSchema,
      ),
    openPlayback,
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
        // Stop delivery locally even if native teardown already made the command unavailable.
        void invoke('unsubscribe_download_events', { subscriptionId }).catch(() => {})
      }
    },
    start: (input) =>
      request('start_downloads', { request: downloadRequestSchema.parse(input) }, startSchema),
    getDirectory: () => request('get_download_directory', {}, z.string().nullable()),
    chooseDirectory: () => request('choose_download_directory', {}, z.string().nullable()),
  }
}
