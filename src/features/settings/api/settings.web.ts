import { effectScope, nextTick, toRaw, watch } from 'vue'
import { settingsSchema } from '@shared/contracts/settings'

import { usePersistentState } from '@/shared/composables/usePersistentState'

import type { SettingsPort } from '@/shared/platform/ports'

export function createWebSettings(): { port: SettingsPort; dispose: () => void } {
  const scope = effectScope(true)
  const state = scope.run(() =>
    usePersistentState('sctv-dl:settings', settingsSchema.parse({}), settingsSchema),
  )!
  const port: SettingsPort = {
    async load() {
      return { value: structuredClone(toRaw(state.value.value)), persisted: state.persisted.value }
    },
    async save(value) {
      state.value.value = settingsSchema.parse(value)
      await nextTick()
      if (!state.persisted.value) {
        throw new Error('设置无法保存到本地存储')
      }
    },
    async subscribe(listener) {
      return scope.run(() =>
        watch(state.value, (value) => listener(structuredClone(toRaw(value))), { deep: true }),
      )!
    },
  }

  return { port, dispose: () => scope.stop() }
}
