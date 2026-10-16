import { invoke } from '@tauri-apps/api/core'
import { z } from 'zod'

import { applicationErrorSchema } from '@shared/contracts/errors'
import { settingsSchema } from '@shared/contracts/settings'

import type { SettingsPort } from '@/shared/platform/ports'

const snapshotSchema = z.object({ value: settingsSchema, persisted: z.boolean() })

async function request(command: string, args: Record<string, unknown> = {}): Promise<unknown> {
  try {
    return await invoke(command, args)
  } catch (cause) {
    const error = applicationErrorSchema.safeParse(cause)
    throw new Error(error.success ? error.data.message : '无法访问本地设置', { cause })
  }
}

export function createTauriSettings(): SettingsPort {
  return {
    load: async () => snapshotSchema.parse(await request('load_settings')),
    async save(value) {
      await request('save_settings', { value: settingsSchema.parse(value) })
    },
    // One application window owns preferences; no independent native writer broadcasts changes.
    subscribe: async () => () => {},
  }
}
