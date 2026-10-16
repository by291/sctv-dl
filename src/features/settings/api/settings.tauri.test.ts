// @vitest-environment happy-dom
import { afterEach, expect, it } from 'vitest'
import { mockIPC, clearMocks } from '@tauri-apps/api/mocks'

import { createTauriSettings } from '@/features/settings/api/settings.tauri'

afterEach(() => clearMocks())

it('validates native snapshots and sends only shared preferences to Rust', async () => {
  const saved: unknown[] = []
  mockIPC((command, args) => {
    if (command === 'load_settings') {
      return { value: { theme: 'dark', quality: 'smooth', favourites: ['1'] }, persisted: true }
    }

    if (command === 'save_settings') {
      saved.push(args)

      return null
    }

    throw new Error(command)
  })
  const port = createTauriSettings()
  expect(await port.load()).toEqual({
    value: { theme: 'dark', quality: 'smooth', favourites: ['1'] },
    persisted: true,
  })
  await port.save({ theme: 'light', quality: 'standard', favourites: [] })
  expect(saved).toEqual([{ value: { theme: 'light', quality: 'standard', favourites: [] } }])
  mockIPC(() => ({ value: {}, persisted: 'invalid' }))
  await expect(port.load()).rejects.toThrow()
  mockIPC(() => {
    throw { code: 'storage', message: 'Cannot save preferences' }
  })
  await expect(port.save({ theme: 'system', quality: 'smooth', favourites: [] })).rejects.toThrow(
    'Cannot save preferences',
  )
})
