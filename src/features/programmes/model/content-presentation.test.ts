import { describe, expect, it } from 'vitest'

import { programmeContentRows } from '@/features/programmes/model/content-presentation'

import type { ProgrammeContent } from '@/features/programmes/model/programme'

function content(id: string, publishedAt: string | null): ProgrammeContent {
  return { id, title: id, publishedAt, cover: null, video: null, smoothVideo: null }
}

describe('programme content presentation', () => {
  const contents = [
    content('late', '2026-10-10 18:55:16'),
    content('missing', null),
    content('full', '2026-10-10 19:00:00'),
    content('early', '2026-10-10 18:41:17'),
    content('invalid', '2026-02-30 18:30:00'),
    content('same', '2026-10-10T10:41:17Z'),
  ]

  it.each([
    { order: 'asc' as const, ids: ['full', 'early', 'same', 'late', 'missing', 'invalid'] },
    { order: 'desc' as const, ids: ['full', 'late', 'early', 'same', 'missing', 'invalid'] },
  ])(
    'pins full episodes and sorts clips in $order order without mutating source data',
    ({ order, ids }) => {
      const original = contents.slice()
      const rows = programmeContentRows(contents, ['full'], order)

      expect(rows.map((row) => row.content.id)).toEqual(ids)
      expect(rows[0]?.fullEpisode).toBe(true)
      expect(contents).toEqual(original)
    },
  )

  it.each(['2026-10-10 18:41:17', '2026-10-10T10:41:17Z', '2026-10-10T18:41:17+08:00'])(
    'displays %s in the broadcast timezone',
    (publishedAt) => {
      const rows = programmeContentRows([content('clip', publishedAt)], [], 'asc')

      expect(rows[0]?.publication).toMatchObject({
        label: '2026-10-10 18:41:17',
        datetime: '2026-10-10T10:41:17.000Z',
      })
    },
  )

  it('keeps multiple full episodes and unavailable publication times stable', () => {
    const rows = programmeContentRows(
      [content('full-a', null), content('clip', ''), content('full-b', '2026-10-10 18:30:00')],
      ['full-a', 'full-b'],
      'desc',
    )

    expect(rows.map((row) => row.content.id)).toEqual(['full-a', 'full-b', 'clip'])
    expect(rows[0]?.publication).toBeNull()
    expect(rows[2]?.publication).toBeNull()
  })
})
