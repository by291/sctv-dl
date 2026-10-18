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

async function settleArchive() {
  for (let i = 0; i < 12; i++) {
    await nextTick()
  }
}

const episode = {
  id: '1',
  title: 'Old',
  cover: null,
  video: null,
  smoothVideo: null,
  publishedAt: null,
}

it('holds content changes during batch selection and preserves rows on refresh failure', async () => {
  const client: ProgrammeApi = {
    programmes: vi.fn(),
    dates: vi.fn().mockResolvedValue([{ id: '10', date: '2026-10-06' }]),
    contents: vi
      .fn()
      .mockResolvedValueOnce([episode])
      .mockResolvedValueOnce([{ ...episode, title: 'New' }])
      .mockRejectedValueOnce(new Error('Offline')),
  }
  const held = ref(true)
  const scope = effectScope()
  const archive = scope.run(() =>
    useProgrammeArchive(ref('1'), client, undefined, { interactionHold: held }),
  )!
  await settleArchive()
  await archive.loadContents()
  expect(archive.contents.value[0]?.title).toBe('Old')
  expect(archive.pendingUpdate.value).toBe(true)
  await archive.acceptUpdate()
  expect(archive.contents.value[0]?.title).toBe('Old')
  held.value = false
  await archive.acceptUpdate()
  expect(archive.contents.value[0]?.title).toBe('New')
  await archive.loadContents()
  expect(archive.contentError.value).toBe('')
  expect(archive.refreshError.value).toContain('Offline')
  scope.stop()
})

it('clears old content and resolves a changed date ID when date updates are accepted', async () => {
  const client: ProgrammeApi = {
    programmes: vi.fn(),
    dates: vi
      .fn()
      .mockResolvedValueOnce([{ id: '10', date: '2026-10-06' }])
      .mockResolvedValueOnce([{ id: '20', date: '2026-10-06' }]),
    contents: vi
      .fn()
      .mockResolvedValueOnce([episode])
      .mockImplementationOnce(() => new Promise(() => {})),
  }
  const scope = effectScope()
  const archive = scope.run(() => useProgrammeArchive(ref('1'), client))!
  await settleArchive()
  await archive.loadDates()
  expect(archive.contents.value).toEqual([episode])
  await archive.acceptUpdate()
  expect(archive.contents.value).toEqual([])
  expect(client.contents).toHaveBeenLastCalledWith('1', '20', expect.any(AbortSignal))
  scope.stop()
})

it('restores an older date before issuing any content request and falls back after deletion', async () => {
  let ready!: () => void
  const saved = ref({
    programmeId: '1',
    dateId: '11',
    date: '2026-10-05',
    sort: 'desc' as const,
    scrollY: 600,
    visitedAt: '2026-10-17T00:00:00Z',
  })
  const pending = new Promise<void>((resolve) => {
    ready = resolve
  })
  const client: ProgrammeApi = {
    programmes: vi.fn(),
    dates: vi
      .fn()
      .mockResolvedValueOnce([
        { id: '10', date: '2026-10-06' },
        { id: '11', date: '2026-10-05' },
      ])
      .mockResolvedValueOnce([{ id: '10', date: '2026-10-06' }]),
    contents: vi.fn().mockResolvedValue([episode]),
  }
  const scope = effectScope()
  const archive = scope.run(() =>
    useProgrammeArchive(ref('1'), client, undefined, {
      restoration: { ready: () => pending, saved },
    }),
  )!
  await settleArchive()
  expect(client.contents).not.toHaveBeenCalled()
  ready()
  await settleArchive()
  expect(client.contents).toHaveBeenCalledExactlyOnceWith('1', '11', expect.any(AbortSignal))
  await archive.loadDates()
  await archive.acceptUpdate()
  await settleArchive()
  expect(archive.selectedDate.value).toBe('2026-10-06')
  expect(archive.selectionNotice.value).not.toBe('')
  scope.stop()
})

it('applies an empty date update without keeping the previous content list', async () => {
  const client: ProgrammeApi = {
    programmes: vi.fn(),
    dates: vi
      .fn()
      .mockResolvedValueOnce([{ id: '10', date: '2026-10-06' }])
      .mockResolvedValueOnce([]),
    contents: vi.fn().mockResolvedValue([episode]),
  }
  const scope = effectScope()
  const archive = scope.run(() => useProgrammeArchive(ref('1'), client))!
  await settleArchive()
  await archive.loadDates()
  await archive.acceptUpdate()
  await settleArchive()
  expect(archive.dates.value).toEqual([])
  expect(archive.contents.value).toEqual([])
  expect(archive.selectedDate.value).toBeNull()
  scope.stop()
})

it('rejects the first A request after A to B to A navigation', async () => {
  let resolveOld!: (value: (typeof episode)[]) => void
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
      .mockResolvedValueOnce([{ ...episode, title: 'B' }])
      .mockResolvedValueOnce([{ ...episode, title: 'Fresh A' }]),
  }
  const scope = effectScope()
  const archive = scope.run(() => useProgrammeArchive(ref('1'), client))!
  await settleArchive()
  archive.selectedDate.value = '2026-10-05'
  await settleArchive()
  archive.selectedDate.value = '2026-10-06'
  await settleArchive()
  resolveOld([{ ...episode, title: 'Old A' }])
  await settleArchive()
  expect(archive.contents.value[0]?.title).toBe('Fresh A')
  expect(archive.pendingUpdate.value).toBe(false)
  scope.stop()
})
