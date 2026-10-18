import { expect, it, vi } from 'vitest'
import { effectScope, ref } from 'vue'
import { archiveBrowseStateSchema } from '@shared/contracts/programme-cache'
import { useArchiveBrowseState } from '@/features/programmes/composables/useArchiveBrowseState'
import type { BrowseStateRead } from '@shared/contracts/programme-cache'
import type { ProgrammeCachePort } from '@/shared/platform/ports'

const saved = {
  programmeId: '1',
  dateId: '10',
  date: '2026-10-06',
  sort: 'desc' as const,
  scrollY: 600,
  visitedAt: '2026-10-17T00:00:00Z',
}

it('hides validation internals and clears a save warning after persistence recovers', async () => {
  const { port } = cache()
  const invalid = archiveBrowseStateSchema.safeParse({ ...saved, scrollY: -24 })
  if (invalid.success) {
    throw new Error('Expected an invalid browse position')
  }

  vi.mocked(port.writeBrowseState).mockRejectedValueOnce(invalid.error)
  const scope = effectScope()
  const state = scope.run(() => useArchiveBrowseState(ref('1'), port))!
  await state.ready

  await state.save(saved)
  expect(state.warning.value).toBe('浏览位置暂时无法保存')

  await state.save(saved)
  expect(state.warning.value).toBe('')
  scope.stop()
})

function cache() {
  let clear: (epoch: string) => void = () => {}

  const port: ProgrammeCachePort = {
    read: vi.fn(),
    write: vi.fn(),
    clear: vi.fn(),
    readBrowseState: vi
      .fn()
      .mockResolvedValue({ epoch: 'old', value: saved, persisted: true, warning: null }),
    writeBrowseState: vi.fn().mockResolvedValue({ accepted: true, persisted: true }),
    subscribeCleared: vi.fn(async (listener) => {
      clear = listener

      return vi.fn()
    }),
  }

  return { port, clear: () => clear('new') }
}

it('restores isolated state and writes a departure before disposal', async () => {
  const { port } = cache()
  const scope = effectScope()
  const state = scope.run(() => useArchiveBrowseState(ref('1'), port))!
  await state.ready
  expect(state.saved.value).toEqual(saved)
  const writing = state.save({ dateId: '10', date: '2026-10-06', sort: 'asc', scrollY: 810 })
  state.dispose()
  await writing
  expect(port.writeBrowseState).toHaveBeenCalledWith(
    expect.objectContaining({ programmeId: '1', scrollY: 810 }),
    'old',
  )
  scope.stop()
})

it('rejects pre-clear reads and never saves them under a new generation', async () => {
  const { port, clear } = cache()
  const scope = effectScope()
  let resolve!: (value: BrowseStateRead) => void
  vi.mocked(port.readBrowseState).mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done
      }),
  )
  const state = scope.run(() => useArchiveBrowseState(ref('1'), port))!
  for (let i = 0; i < 4; i++) {
    await Promise.resolve()
  }

  clear()
  resolve({ epoch: 'old', value: saved, persisted: true, warning: null })
  await state.ready
  await state.save(saved)
  expect(state.saved.value).toBeNull()
  expect(port.writeBrowseState).not.toHaveBeenCalled()
  scope.stop()
})

it('does not reuse a previous programme when its delayed read finishes', async () => {
  const { port } = cache()
  const scope = effectScope()
  const id = ref('1')
  let resolve!: (value: BrowseStateRead) => void
  vi.mocked(port.readBrowseState)
    .mockImplementationOnce(
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    .mockResolvedValueOnce({ epoch: 'old', value: null, persisted: true, warning: null })
  const state = scope.run(() => useArchiveBrowseState(id, port))!
  for (let i = 0; i < 4; i++) {
    await Promise.resolve()
  }

  id.value = '2'
  await state.ready
  resolve({ epoch: 'old', value: saved, persisted: true, warning: null })
  await Promise.resolve()
  expect(state.saved.value).toBeNull()
  scope.stop()
})

it('subscribes to clear before reading a browse position', async () => {
  const { port } = cache()
  let connected!: (stop: () => void) => void
  vi.mocked(port.subscribeCleared).mockReturnValue(
    new Promise((resolve) => {
      connected = resolve
    }),
  )
  const scope = effectScope()
  const state = scope.run(() => useArchiveBrowseState(ref('1'), port))!
  await Promise.resolve()
  expect(port.readBrowseState).not.toHaveBeenCalled()
  connected(() => {})
  await state.ready
  expect(state.saved.value).toEqual(saved)
  scope.stop()
})
