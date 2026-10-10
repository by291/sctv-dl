// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { nextTick } from 'vue'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'

beforeEach(() => {
  localStorage.clear()
  setActivePinia(createPinia())
})

describe('settings store', () => {
  it('keeps preference refs connected after another tab replaces saved data', async () => {
    const store = useSettingsStore()
    const newValue = JSON.stringify({ quality: 'smooth', theme: 'dark', favourites: ['1'] })
    localStorage.setItem('sctv-dl:settings', newValue)
    window.dispatchEvent(
      new StorageEvent('storage', { key: 'sctv-dl:settings', newValue, storageArea: localStorage }),
    )
    await nextTick()
    expect(store.theme).toBe('dark')
    expect(store.quality).toBe('smooth')
    store.theme = 'light'
    await nextTick()
    expect(JSON.parse(localStorage.getItem('sctv-dl:settings')!).theme).toBe('light')
    store.$dispose()
  })
})
