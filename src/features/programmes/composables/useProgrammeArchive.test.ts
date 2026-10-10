import { describe, expect, it, vi } from 'vitest'
import { effectScope, nextTick, ref } from 'vue'
import { useProgrammeArchive } from '@/features/programmes/composables/useProgrammeArchive'
import type { ProgrammeApi } from '@/features/programmes/api/programme-api'
import type { ProgrammeDate } from '@/features/programmes/model/programme'

describe('programme archive requests', () => {
  it('ignores a stale contents result when the selected date changes', async () => {
    let resolveOld!: (value: []) => void
    const client: ProgrammeApi = {
      programmes: vi.fn(),
      dates: vi.fn().mockResolvedValue([
        { id: '10', date: '2026-10-06' },
        { id: '11', date: '2026-10-05' },
      ]),
      contents: vi
        .fn()
        .mockImplementationOnce(
          () =>
            new Promise((resolve) => {
              resolveOld = resolve
            }),
        )
        .mockResolvedValueOnce([
          {
            id: '2',
            title: '新日期',
            cover: null,
            video: null,
            smoothVideo: null,
            publishedAt: null,
          },
        ]),
    }
    const scope = effectScope()
    const archive = scope.run(() => useProgrammeArchive(ref('1'), client))!
    await nextTick()
    await nextTick()
    archive.selectedDate.value = '2026-10-05'
    await nextTick()
    await nextTick()
    resolveOld([])
    await nextTick()
    expect(archive.contents.value[0]?.id).toBe('2')
    scope.stop()
  })

  it('does not let a superseded date request overwrite the new programme', async () => {
    let resolveOld!: (value: ProgrammeDate[]) => void
    const client: ProgrammeApi = {
      programmes: vi.fn(),
      dates: vi
        .fn()
        .mockImplementationOnce(
          () =>
            new Promise((resolve) => {
              resolveOld = resolve
            }),
        )
        .mockResolvedValueOnce([{ id: '20', date: '2026-10-06' }]),
      contents: vi.fn().mockResolvedValue([]),
    }
    const programmeId = ref('1')
    const scope = effectScope()
    const archive = scope.run(() => useProgrammeArchive(programmeId, client))!
    programmeId.value = '2'
    await nextTick()
    await nextTick()
    resolveOld([{ id: '10', date: '2026-10-05' }])
    await nextTick()
    expect(archive.dates.value).toEqual([{ id: '20', date: '2026-10-06' }])
    expect(archive.selectedDate.value).toBe('2026-10-06')
    scope.stop()
  })

  it('finishes empty archives and does not request contents without a date', async () => {
    const client: ProgrammeApi = {
      programmes: vi.fn(),
      dates: vi.fn().mockResolvedValue([]),
      contents: vi.fn(),
    }
    const scope = effectScope()
    const archive = scope.run(() => useProgrammeArchive(ref('1'), client))!
    await nextTick()
    expect(archive.loadingDates.value).toBe(false)
    expect(archive.selectedDate.value).toBeNull()
    expect(client.contents).not.toHaveBeenCalled()
    scope.stop()
  })

  it('cancels pending work when its owning scope is disposed', async () => {
    let signal: AbortSignal | undefined
    const client: ProgrammeApi = {
      programmes: vi.fn(),
      contents: vi.fn(),
      dates: vi.fn<ProgrammeApi['dates']>((_id, value) => {
        signal = value

        return new Promise<ProgrammeDate[]>(() => {})
      }),
    }
    const scope = effectScope()
    scope.run(() => useProgrammeArchive(ref('1'), client))
    scope.stop()
    expect(signal?.aborted).toBe(true)
  })
})
