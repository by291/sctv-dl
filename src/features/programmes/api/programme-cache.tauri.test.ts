// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { invoke } from '@tauri-apps/api/core'
import { createTauriProgrammeCache } from '@/features/programmes/api/programme-cache.tauri'
import { pageScrollPosition } from '@/shared/navigation/page-scroll'

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn() }))
afterEach(() => vi.resetAllMocks())
describe('native programme cache adapter', () => {
  it('persists a captured WebKit bounce at the top through the native command', async () => {
    const owner = createTauriProgrammeCache()
    const element = document.createElement('div')
    element.scrollTop = -24.5
    vi.mocked(invoke).mockResolvedValueOnce({ accepted: true, persisted: true })

    await owner.port.writeBrowseState(
      {
        programmeId: '1',
        dateId: '10',
        date: '2026-10-17',
        sort: 'desc',
        scrollY: pageScrollPosition(element).top,
        visitedAt: '2026-10-17T00:00:00Z',
      },
      'current',
    )

    expect(invoke).toHaveBeenCalledWith('write_archive_browse_state', {
      value: expect.objectContaining({ programmeId: '1', scrollY: 0 }),
      expectedEpoch: 'current',
    })
    owner.dispose()
  })
  it('validates command responses and keeps notifications scoped to active subscribers', async () => {
    const owner = createTauriProgrammeCache()
    const listener = vi.fn()
    const stop = await owner.port.subscribeCleared(listener)
    vi.mocked(invoke).mockResolvedValueOnce({ epoch: 'fresh' })
    expect(await owner.port.clear()).toEqual({ epoch: 'fresh' })
    expect(listener).toHaveBeenCalledWith('fresh')
    stop()
    vi.mocked(invoke).mockResolvedValueOnce({ epoch: 'next' })
    await owner.port.clear()
    expect(listener).toHaveBeenCalledTimes(1)
    vi.mocked(invoke).mockResolvedValueOnce({
      epoch: 'next',
      snapshot: { invalid: true },
      persisted: true,
      warning: null,
    })
    await expect(owner.port.read({ kind: 'catalogue' })).rejects.toThrow()
    owner.dispose()
    await expect(owner.port.read({ kind: 'catalogue' })).rejects.toThrow()
  })
  it('uses only typed domain arguments and rejects malformed keys before IPC', async () => {
    const owner = createTauriProgrammeCache()
    vi.mocked(invoke).mockResolvedValueOnce({
      epoch: 'e',
      snapshot: null,
      accepted: false,
      persisted: true,
      warning: null,
    })
    await owner.port.write({ kind: 'dates', programmeId: '1', items: [] }, 'old')
    expect(invoke).toHaveBeenCalledWith('write_programme_cache', {
      payload: { kind: 'dates', programmeId: '1', items: [] },
      expectedEpoch: 'old',
    })
    expect(() => owner.port.read({ kind: 'dates', programmeId: '../bad' })).toThrow()
    owner.dispose()
  })
})
