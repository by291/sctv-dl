// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { mockIPC, clearMocks } from '@tauri-apps/api/mocks'
import { createPlatform } from '@/platform/create-platform'

afterEach(() => {
  clearMocks()
  vi.unstubAllGlobals()
})

it('composes the browser platform without native IPC', async () => {
  const platform = await createPlatform()
  expect(platform.kind).toBe('web')
  expect(platform.downloads.kind).toBe('browser')
  await platform.dispose()
})

it('composes only native services inside Tauri and uses Rust for settings', async () => {
  vi.stubGlobal('isTauri', true)
  mockIPC((command) => {
    if (command === 'load_settings') {
      return { value: { theme: 'dark', quality: 'smooth', favourites: [] }, persisted: true }
    }

    throw new Error(`Unexpected command ${command}`)
  })
  const platform = await createPlatform()
  expect(platform.kind).toBe('tauri')
  expect(platform.downloads.kind).toBe('native')
  expect((await platform.settings.load()).value.theme).toBe('dark')
  await platform.dispose()
})
