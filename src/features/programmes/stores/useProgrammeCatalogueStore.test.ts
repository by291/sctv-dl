// @vitest-environment happy-dom
import { expect, it, vi } from 'vitest'
import { createApp } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'

function fixture() {
  const platform = createPlatformFixture()
  const pinia = createPinia()
  createApp({}).provide(platformKey, platform).use(pinia)
  setActivePinia(pinia)

  return { platform, store: useProgrammeCatalogueStore() }
}

it('holds changed catalogue refreshes while retaining usable rows after errors', async () => {
  const { platform, store } = fixture()
  platform.programmes.programmes = vi
    .fn()
    .mockResolvedValueOnce([{ id: '1', name: 'Old', cover: null }])
    .mockResolvedValueOnce([{ id: '2', name: 'New', cover: null }])
    .mockRejectedValueOnce(new Error('Offline'))
  await store.load()
  await store.load(true)
  expect(store.programmes[0]?.name).toBe('Old')
  expect(store.pendingUpdate).toBe(true)
  await store.acceptUpdate()
  expect(store.programmes[0]?.name).toBe('New')
  await store.load(true)
  expect(store.error).toBe('')
  expect(store.refreshError).toBe('Offline')
  expect(store.programmes[0]?.name).toBe('New')
  store.$dispose()
})

it('does not repeatedly fetch a successfully loaded empty catalogue', async () => {
  const { platform, store } = fixture()
  platform.programmes.programmes = vi.fn().mockResolvedValue([])
  await store.load()
  await store.load()
  expect(platform.programmes.programmes).toHaveBeenCalledOnce()
  store.$dispose()
})
