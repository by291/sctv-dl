// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { clearMocks, mockIPC } from '@tauri-apps/api/mocks'
import { effectScope, nextTick, ref } from 'vue'
import { flushPromises } from '@vue/test-utils'

import { useProgrammeArchive } from '@/features/programmes/composables/useProgrammeArchive'

import { createTauriProgrammeApi } from '@/features/programmes/api/programme-api.tauri'

afterEach(() => {
  clearMocks()
  vi.restoreAllMocks()
})

it('validates normalized command results and sends string references with unique request IDs', async () => {
  const calls: Array<{ command: string; payload: unknown }> = []
  mockIPC((command, payload) => {
    calls.push({ command, payload })
    if (command === 'list_programmes') {
      return [{ id: '1', name: 'News', cover: null }]
    }

    if (command === 'list_programme_dates') {
      return [{ id: '2', date: '2026-10-15' }]
    }

    return [
      { id: '3', title: 'Clip', cover: null, video: null, smoothVideo: null, publishedAt: null },
    ]
  })
  const api = createTauriProgrammeApi()
  expect(await api.programmes()).toEqual([{ id: '1', name: 'News', cover: null }])
  expect(await api.dates('1')).toEqual([{ id: '2', date: '2026-10-15' }])
  expect((await api.contents('1', '2'))[0]?.id).toBe('3')
  expect(calls.map((call) => call.command)).toEqual([
    'list_programmes',
    'list_programme_dates',
    'list_programme_contents',
  ])
  expect(calls[1]?.payload).toMatchObject({ programmeId: '1' })
  expect(calls[2]?.payload).toMatchObject({ programmeId: '1', dateId: '2' })
  const ids = calls.map((call) => (call.payload as { requestId: string }).requestId)
  expect(new Set(ids).size).toBe(3)
  for (const id of ids) {
    expect(id).toMatch(/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/)
  }
})

it('does not invoke native work for an already aborted signal or invalid references', async () => {
  const handler = vi.fn()
  mockIPC(handler)
  const api = createTauriProgrammeApi()
  const controller = new AbortController()
  controller.abort()
  await expect(api.programmes(controller.signal)).rejects.toMatchObject({ name: 'AbortError' })
  await expect(api.dates('../1')).rejects.toThrow('ID')
  await expect(api.contents('1', '')).rejects.toThrow('ID')
  expect(handler).not.toHaveBeenCalled()
})

it('rejects promptly on abort and cancels the same native request even if it later resolves', async () => {
  let complete!: (value: unknown) => void
  const calls: Array<{ command: string; requestId: unknown }> = []
  mockIPC((command, payload) => {
    const requestId = (payload as { requestId: unknown }).requestId
    calls.push({ command, requestId })

    return command === 'cancel_request'
      ? undefined
      : new Promise((resolve) => {
          complete = resolve
        })
  })
  const controller = new AbortController()
  const request = createTauriProgrammeApi().programmes(controller.signal)
  const rejected = expect(request).rejects.toMatchObject({ name: 'AbortError' })
  controller.abort()
  await rejected
  expect(calls).toEqual([
    { command: 'list_programmes', requestId: expect.any(String) },
    { command: 'cancel_request', requestId: calls[0]?.requestId },
  ])
  complete([{ id: '1', name: 'Late', cover: null }])
  await Promise.resolve()
})

it.each(['success', 'error'])('removes abort listeners after terminal %s', async (outcome) => {
  const commands: string[] = []
  mockIPC((command) => {
    commands.push(command)
    if (outcome === 'error') {
      return Promise.reject({ code: 'upstream', message: 'Service failed' })
    }

    return []
  })
  const controller = new AbortController()
  const remove = vi.spyOn(controller.signal, 'removeEventListener')
  const request = createTauriProgrammeApi().programmes(controller.signal)
  if (outcome === 'success') {
    await expect(request).resolves.toEqual([])
  } else {
    await expect(request).rejects.toThrow('Service failed')
  }

  expect(remove).toHaveBeenCalledWith('abort', expect.any(Function))
  controller.abort()
  expect(commands).toEqual(['list_programmes'])
})

it('rejects malformed DTOs and maps native cancellation to AbortError', async () => {
  mockIPC(() => [{ id: 1, name: 'Bad', cover: null }])
  await expect(createTauriProgrammeApi().programmes()).rejects.toThrow('数据格式')
  mockIPC(() => Promise.reject({ code: 'cancelled', message: 'Cancelled' }))
  await expect(createTauriProgrammeApi().programmes()).rejects.toMatchObject({ name: 'AbortError' })
})

it('settles cancellation when the cancel command itself fails', async () => {
  mockIPC((command) =>
    command === 'cancel_request'
      ? Promise.reject(new Error('IPC unavailable'))
      : new Promise(() => {}),
  )
  const controller = new AbortController()
  const request = createTauriProgrammeApi().programmes(controller.signal)
  const rejected = expect(request).rejects.toMatchObject({ name: 'AbortError' })
  controller.abort()
  await rejected
})

it('keeps the newest archive when native replies arrive after a programme switch', async () => {
  const pending = new Map<string, (value: unknown) => void>()
  mockIPC((command, payload) => {
    if (command === 'cancel_request') {
      return undefined
    }

    if (command === 'list_programme_contents') {
      return []
    }

    return new Promise((resolve) => {
      pending.set((payload as { programmeId: string }).programmeId, resolve)
    })
  })
  const scope = effectScope()
  const programmeId = ref('1')
  const archive = scope.run(() => useProgrammeArchive(programmeId, createTauriProgrammeApi()))!
  try {
    programmeId.value = '2'
    await nextTick()
    pending.get('2')!([{ id: '22', date: '2026-10-15' }])
    await flushPromises()
    pending.get('1')!([{ id: '11', date: '2026-10-14' }])
    await flushPromises()
    expect(archive.dates.value).toEqual([{ id: '22', date: '2026-10-15' }])
    expect(archive.selectedDate.value).toBe('2026-10-15')
    expect(archive.dateError.value).toBe('')
  } finally {
    scope.stop()
  }
})
