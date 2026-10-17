import { describe, expect, it } from 'vitest'

import { historyKey, isHistoryCompleted, resumePosition } from './history.ts'

describe('viewing history policy', () => {
  it('uses the exact completion boundary and ignores unknown duration', () => {
    expect(isHistoryCompleted({ positionMs: 94999, durationMs: 100000, ended: false })).toBe(false)
    expect(isHistoryCompleted({ positionMs: 95000, durationMs: 100000, ended: false })).toBe(true)
    expect(isHistoryCompleted({ positionMs: 999999, durationMs: null, ended: false })).toBe(false)
    expect(isHistoryCompleted({ positionMs: 0, durationMs: 0, ended: false })).toBe(false)
    expect(isHistoryCompleted({ positionMs: 0, durationMs: null, ended: true })).toBe(true)
    expect(isHistoryCompleted({ positionMs: 1000, durationMs: 100000, ended: false })).toBe(false)
  })

  it('reopens completed entries at zero and uses content identity across qualities', () => {
    const entry = {
      content: { programmeId: '9007199254740993', dateId: '2', contentId: '3' },
      programmeName: 'News',
      broadcastDate: '2026-10-17',
      title: 'Episode',
      cover: null,
      positionMs: 300000,
      durationMs: 600000,
      viewedAt: '2026-10-17T00:00:00Z',
      completed: false,
    }
    expect(resumePosition(entry)).toBe(300000)
    expect(resumePosition({ ...entry, completed: true })).toBe(0)
    expect(historyKey(entry.content)).not.toBe(historyKey({ ...entry.content, contentId: '4' }))
  })
})
