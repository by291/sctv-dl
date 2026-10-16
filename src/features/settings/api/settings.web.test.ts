// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { nextTick } from 'vue'

import { createWebSettings } from '@/features/settings/api/settings.web'

import type { Settings } from '@shared/contracts/settings'

let adapter: ReturnType<typeof createWebSettings> | undefined
beforeEach(() => localStorage.clear())
afterEach(() => {
  adapter?.dispose()
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

it('keeps the existing storage key and stops observing other tabs after disposal', async () => {
  adapter = createWebSettings()
  const updates: Settings[] = []
  const unsubscribe = await adapter.port.subscribe((value) => updates.push(value))
  await adapter.port.save({ quality: 'smooth', theme: 'dark', favourites: ['1'] })
  expect(JSON.parse(localStorage.getItem('sctv-dl:settings')!)).toEqual({
    quality: 'smooth',
    theme: 'dark',
    favourites: ['1'],
  })
  expect(updates.at(-1)?.theme).toBe('dark')
  unsubscribe()
  adapter.dispose()
  window.dispatchEvent(
    new StorageEvent('storage', {
      key: 'sctv-dl:settings',
      newValue: '{"theme":"light"}',
      storageArea: localStorage,
    }),
  )
  await nextTick()
  expect((await adapter.port.load()).value.theme).toBe('dark')
})

it('reports a failed save while retaining usable in-memory preferences', async () => {
  const storage = localStorage
  vi.stubGlobal(
    'localStorage',
    new Proxy(storage, {
      get(target, key) {
        if (key === 'setItem') {
          return () => {
            throw new Error('quota')
          }
        }

        const value = Reflect.get(target, key)

        return typeof value === 'function' ? value.bind(target) : value
      },
    }),
  )
  adapter = createWebSettings()
  await expect(
    adapter.port.save({ quality: 'smooth', theme: 'dark', favourites: [] }),
  ).rejects.toThrow('保存')
  expect(await adapter.port.load()).toEqual({
    value: { quality: 'smooth', theme: 'dark', favourites: [] },
    persisted: false,
  })
})

it('defaults damaged data, ignores obsolete downloads, and receives validated cross-tab changes', async () => {
  localStorage.setItem('sctv-dl:settings', 'broken')
  localStorage.setItem('sctv-dl:downloads', '{"theme":"dark"}')
  adapter = createWebSettings()
  expect((await adapter.port.load()).value).toEqual({
    quality: 'standard',
    theme: 'system',
    favourites: [],
  })
  window.dispatchEvent(
    new StorageEvent('storage', {
      key: 'sctv-dl:settings',
      newValue: '{"theme":"dark","quality":"wrong","favourites":["1",2,"1"]}',
      storageArea: localStorage,
    }),
  )
  await nextTick()
  expect((await adapter.port.load()).value).toEqual({
    quality: 'standard',
    theme: 'dark',
    favourites: ['1'],
  })
  expect(localStorage.getItem('sctv-dl:downloads')).toBe('{"theme":"dark"}')
})
