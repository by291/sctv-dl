// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { nextTick } from 'vue'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'

import type { Settings, SettingsSnapshot } from '@shared/contracts/settings'
import type { SettingsPort } from '@/shared/platform/ports'

import { createWebSettings } from '@/features/settings/api/settings.web'

let adapter: ReturnType<typeof createWebSettings> | undefined
afterEach(() => adapter?.dispose())

beforeEach(() => {
  localStorage.clear()
  setActivePinia(createPinia())
})

describe('settings store', () => {
  it('keeps preference refs connected after another tab replaces saved data', async () => {
    const store = useSettingsStore()
    adapter = createWebSettings()
    await store.hydrate(adapter.port)
    const newValue = JSON.stringify({ quality: 'smooth', theme: 'dark', favourites: ['1'] })
    localStorage.setItem('sctv-dl:settings', newValue)
    window.dispatchEvent(
      new StorageEvent('storage', { key: 'sctv-dl:settings', newValue, storageArea: localStorage }),
    )
    await nextTick()
    expect(store.theme).toBe('dark')
    expect(store.quality).toBe('smooth')
    store.theme = 'light'
    await store.flush()
    await nextTick()
    expect(JSON.parse(localStorage.getItem('sctv-dl:settings')!).theme).toBe('light')
    store.$dispose()
  })
})

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((done) => {
    resolve = done
  })

  return { promise, resolve }
}

it('keeps a newer edit when hydration resolves late and serializes writes', async () => {
  const store = useSettingsStore()
  const load = deferred<SettingsSnapshot>()
  const firstSave = deferred<void>()
  const saved: string[] = []
  const port: SettingsPort = {
    load: () => load.promise,
    subscribe: async () => () => {},
    async save(value) {
      saved.push(value.theme)
      if (saved.length === 1) {
        await firstSave.promise
      }
    },
  }
  const ready = store.hydrate(port)
  store.theme = 'dark'
  load.resolve({ value: { theme: 'light', quality: 'smooth', favourites: ['1'] }, persisted: true })
  await ready
  expect(store.theme).toBe('dark')
  store.theme = 'light'
  await nextTick()
  expect(saved).toEqual(['dark'])
  firstSave.resolve()
  await store.flush()
  expect(saved).toEqual(['dark', 'light'])
  store.$dispose()
})

it('keeps failed edits usable and releases late subscriptions on disposal', async () => {
  const store = useSettingsStore()
  const subscription = deferred<() => void>()
  let disposed = 0
  const port: SettingsPort = {
    load: async () => ({
      value: { theme: 'system', quality: 'standard', favourites: [] },
      persisted: true,
    }),
    subscribe: () => subscription.promise,
    save: async () => {
      throw new Error('disk full')
    },
  }
  const ready = store.hydrate(port)
  subscription.resolve(() => {
    disposed++
  })
  await ready
  store.theme = 'dark'
  await store.flush()
  expect(store.theme).toBe('dark')
  expect(store.persisted).toBe(false)
  store.$dispose()
  expect(disposed).toBe(1)
})

it('does not apply its older save notification over a newer local edit', async () => {
  const store = useSettingsStore()
  let notify!: (value: Settings) => void
  const writing = deferred<void>()
  let writes = 0
  await store.hydrate({
    load: async () => ({
      value: { theme: 'system', quality: 'standard', favourites: [] },
      persisted: true,
    }),
    subscribe: async (listener) => {
      notify = listener

      return () => {}
    },
    save: async (value) => {
      if (++writes === 1) {
        await writing.promise
      }

      notify(value)
    },
  })
  store.theme = 'dark'
  await nextTick()
  store.theme = 'light'
  notify({ theme: 'dark', quality: 'standard', favourites: [] })
  expect(store.theme).toBe('light')
  writing.resolve()
  await store.flush()
  expect(store.theme).toBe('light')
  store.$dispose()
})

it('preserves a subscription update that arrives during snapshot loading', async () => {
  const store = useSettingsStore()
  const loaded = deferred<SettingsSnapshot>()
  let notify!: (value: Settings) => void
  const ready = store.hydrate({
    subscribe: async (listener) => {
      notify = listener

      return () => {}
    },
    load: () => loaded.promise,
    save: async () => {},
  })
  await nextTick()
  notify({ theme: 'dark', quality: 'smooth', favourites: ['3'] })
  loaded.resolve({
    value: { theme: 'light', quality: 'standard', favourites: [] },
    persisted: true,
  })
  await ready
  expect(store.theme).toBe('dark')
  expect(store.favourites).toEqual(['3'])
  store.$dispose()
})
