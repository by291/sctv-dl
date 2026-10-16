import { describe, expect, it } from 'vitest'

import { isFullEpisode } from '@/features/programmes/model/full-episodes'

describe('full episode matching', () => {
  it.each(['栏目（2026.10.06）', '栏目(2026.10.06)', ' 栏目 （ 2026.10.06 ） '])(
    'recognizes a programme and broadcast date in %s',
    (title) => {
      expect(isFullEpisode(title, '栏目', '2026-10-06')).toBe(true)
    },
  )

  it.each([
    { title: '片段', programme: '栏目', date: '2026-10-06' },
    { title: '其他栏目（2026.10.06）', programme: '栏目', date: '2026-10-06' },
    { title: '栏目（2026.10.05）', programme: '栏目', date: '2026-10-06' },
    { title: '栏目（2026.10.06）精彩片段', programme: '栏目', date: '2026-10-06' },
    { title: '栏目（2026.10.06）', programme: '', date: '2026-10-06' },
    { title: '栏目（2026.10.06）', programme: '栏目', date: null },
  ])(
    'rejects a title without the exact programme and date: $title',
    ({ title, programme, date }) => {
      expect(isFullEpisode(title, programme, date)).toBe(false)
    },
  )
})
