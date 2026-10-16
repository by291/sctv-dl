// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { mockIPC, clearMocks } from '@tauri-apps/api/mocks'
import { createTauriPlayback } from '@/features/programmes/api/playback.tauri'

afterEach(() => clearMocks())
const input = { programmeId: '1', dateId: '2', contentId: '3', quality: 'standard' as const }
const session = {
  id: 'session',
  selectedQuality: 'standard',
  sources: [{ quality: 'standard', url: 'http://127.0.0.1:3210/media/token/standard' }],
}

it('closes sessions returned after cancellation and releases all owned work on disposal', async () => {
  let complete!: (value: unknown) => void
  const calls: { command: string; args: unknown }[] = []
  mockIPC((command, args) => {
    calls.push({ command, args })
    if (command === 'open_playback') {
      return new Promise((resolve) => {
        complete = resolve
      })
    }

    return null
  })
  const playback = createTauriPlayback()
  const abort = new AbortController()
  const pending = playback.open(input, abort.signal)
  abort.abort()
  await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
  complete(session)
  await new Promise((resolve) => setTimeout(resolve, 0))
  expect(calls.some((call) => call.command === 'cancel_request')).toBe(true)
  expect(
    calls.filter((call) => call.command === 'close_playback').map((call) => call.args),
  ).toEqual([{ sessionId: 'session' }])
  mockIPC((command) => (command === 'open_playback' ? session : null))
  expect(await playback.open(input)).toEqual(session)
  await playback.dispose()
  await expect(playback.open(input)).rejects.toMatchObject({ name: 'AbortError' })
})

it('validates payloads and does not invoke an already cancelled open', async () => {
  const invoke = vi.fn(() => session)
  mockIPC(invoke)
  const playback = createTauriPlayback()
  const abort = new AbortController()
  abort.abort()
  await expect(playback.open(input, abort.signal)).rejects.toMatchObject({ name: 'AbortError' })
  expect(invoke).not.toHaveBeenCalled()
  mockIPC(() => ({ id: 'broken', sources: [] }))
  await expect(playback.open(input)).rejects.toThrow('格式')
  await playback.dispose()
})

it('releases an identifiable native session even when the returned payload is malformed', async () => {
  const call = vi.fn((command: string) =>
    command === 'open_playback' ? { id: 'broken', sources: [] } : null,
  )
  mockIPC(call)
  const playback = createTauriPlayback()
  await expect(playback.open(input)).rejects.toThrow('格式')
  expect(call).toHaveBeenCalledWith('close_playback', { sessionId: 'broken' })
})
