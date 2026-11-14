import { z } from 'zod'

import { settingsSchema } from '@shared/contracts/settings'
import { invokeValidated } from '@/shared/platform/invoke-validated.tauri'

import type { SettingsPort } from '@/shared/platform/ports'

const snapshotSchema = z.object({ value: settingsSchema, persisted: z.boolean() })

const messages = { failure: '无法访问本地设置', invalid: '本地设置数据格式异常，请检查客户端版本' }

// Read and write validated settings through native IPC.
export function createTauriSettings(): SettingsPort {
  return {
    load: () =>
      invokeValidated({
        command: 'load_settings',
        parameters: {},
        schema: snapshotSchema,
        messages,
      }),
    async save(value) {
      await invokeValidated({
        command: 'save_settings',
        parameters: { value: settingsSchema.parse(value) },
        schema: z.null(),
        messages,
      })
    },
    // One application window owns preferences; no independent native writer broadcasts changes.
    subscribe: async () => () => {},
  }
}
