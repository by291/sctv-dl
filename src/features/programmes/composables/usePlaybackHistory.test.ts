import { afterEach, describe, expect, it, vi } from 'vitest'

import { usePlaybackHistory } from '@/features/programmes/composables/usePlaybackHistory'

import type { HistoryMetadata } from '@shared/contracts/history'
import type { HistoryPort } from '@/shared/platform/ports'
import type { PlaybackSnapshot } from '@/features/programmes/model/playback-state'

const metadata: HistoryMetadata = {
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  programmeName: 'News',
  title: 'Episode',
  broadcastDate: '2026-10-17',
  cover: null,
}
const snapshot: PlaybackSnapshot = {
  positionMs: 300000,
  durationMs: 600000,
  speed: 1.5,
  quality: 'smooth',
  playing: false,
  ended: false,
  initialized: true,
}

function fixture(completed = false) {
  return {
    begin: vi.fn().mockResolvedValue({
      id: 'history-session',
      entry: {
        ...metadata,
        positionMs: 300000,
        durationMs: 600000,
        viewedAt: '2026-10-17T00:00:00Z',
        completed,
      },
    }),
    record: vi.fn().mockResolvedValue({ accepted: true, persisted: true }),
    end: vi.fn().mockResolvedValue(undefined),
    list: vi.fn(),
    remove: vi.fn(),
    clear: vi.fn(),
    subscribe: vi.fn(),
    flush: vi.fn(),
    getWriteRevision: () => 0,
  } satisfies HistoryPort
}

afterEach(() => vi.useRealTimers())

describe('playback history capture', () => {
  it('loads paused resume intent without recording requested or unsettled progress', async () => {
    const port = fixture()
    const history = usePlaybackHistory(port, metadata)
    expect(await history.ready).toEqual({ positionMs: 300000, speed: 1, playing: false })
    history.update({ ...snapshot, initialized: false }, 'progress')
    await history.captureAndSave()
    expect(port.record).not.toHaveBeenCalled()
    await history.dispose()
  })

  it('reopens completed history at zero', async () => {
    const history = usePlaybackHistory(fixture(true), metadata)
    expect(await history.ready).toMatchObject({ positionMs: 0, playing: false })
    await history.dispose()
  })

  it('throttles forward progress and saves committed seek, pause and capture immediately', async () => {
    vi.useFakeTimers()
    const port = fixture()
    const history = usePlaybackHistory(port, metadata)
    await history.ready
    history.update(snapshot, 'progress')
    history.update({ ...snapshot, positionMs: 301000 }, 'progress')
    await Promise.resolve()
    expect(port.record).toHaveBeenCalledTimes(1)
    vi.advanceTimersByTime(5000)
    history.update({ ...snapshot, positionMs: 306000 }, 'progress')
    history.update({ ...snapshot, positionMs: 100000 }, 'seek')
    history.update({ ...snapshot, positionMs: 101000 }, 'pause')
    await history.captureAndSave()
    expect(port.record.mock.calls.map(([, sample]) => sample.positionMs)).toEqual([
      300000, 306000, 100000, 101000, 101000,
    ])
    await history.dispose()
  })

  it('retries a failed write with its original sequence and retains playback', async () => {
    const port = fixture()
    port.record.mockRejectedValueOnce(new Error('Storage full'))
    const history = usePlaybackHistory(port, metadata)
    await history.ready
    history.update(snapshot, 'pause')
    await history.settled()
    expect(history.warning.value).toContain('Storage full')
    await history.retry()
    expect(port.record.mock.calls.map(([, sample]) => sample.sequence)).toEqual([1, 1])
    expect(history.warning.value).toBe('')
    await history.dispose()
  })

  it('ends a late begin exactly once and does not record after disposal', async () => {
    const port = fixture()
    let resolve!: (session: { id: string; entry: null }) => void
    port.begin.mockImplementation(
      () =>
        new Promise((done) => {
          resolve = done
        }),
    )
    const history = usePlaybackHistory(port, metadata)
    const disposed = history.dispose()
    resolve({ id: 'late', entry: null })
    await disposed
    history.update(snapshot, 'pause')
    await history.dispose()
    expect(port.record).not.toHaveBeenCalled()
    expect(port.end).toHaveBeenCalledExactlyOnceWith('late')
  })
})

it('ends a history session whose retry finishes after disposal', async () => {
  const port = fixture()
  port.begin.mockRejectedValueOnce(new Error('Temporarily unavailable'))
  const history = usePlaybackHistory(port, metadata)
  await history.ready
  let resolve!: (session: { id: string; entry: null }) => void
  port.begin.mockImplementationOnce(
    () =>
      new Promise((done) => {
        resolve = done
      }),
  )
  const retry = history.retry()
  await Promise.resolve()
  await history.dispose()
  resolve({ id: 'late-retry', entry: null })
  await retry
  expect(port.end).toHaveBeenCalledExactlyOnceWith('late-retry')
  expect(port.record).not.toHaveBeenCalled()
})
