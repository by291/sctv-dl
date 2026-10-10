import { describe, expect, it, vi } from 'vitest'
import { createProgrammeApi } from '@/features/programmes/api/programme-api'
import { mediaUrl, imageUrl } from '@/features/programmes/api/upstream-urls'

const reply = (data: unknown, rs = 200) =>
  new Response(JSON.stringify({ rs, data, error: '服务错误' }), {
    headers: { 'content-type': 'application/json' },
  })

describe('programme API', () => {
  it('retains large string IDs and expands relative video URLs', async () => {
    const fetcher = vi.fn().mockResolvedValue(
      reply([
        {
          id: '2107426129285414913',
          title: '四川新闻联播',
          cover: '/a.jpg',
          video: 'NewsMedia/a.mp4',
          videoStandard: null,
        },
      ]),
    )
    const contents = await createProgrammeApi('/api', fetcher).contents('1', '2107420533961056258')
    expect(fetcher.mock.calls[0]?.[0]).toBe(
      '/api/app/v1/programs/1/dates/2107420533961056258/contents/list',
    )
    expect(contents[0]).toMatchObject({
      id: '2107426129285414913',
      video: 'https://fscgc.scgchc.com/NewsMedia/a.mp4',
      smoothVideo: null,
    })
  })
  it('rejects API business errors even when HTTP succeeds', async () => {
    await expect(
      createProgrammeApi('/api', vi.fn().mockResolvedValue(reply(null, 401))).programmes(),
    ).rejects.toThrow('服务错误')
  })

  it('accepts content without a smooth variant instead of rejecting the entire broadcast', async () => {
    const fetcher = vi.fn().mockResolvedValue(
      reply([
        {
          id: '2106339065831817217',
          title: 'Broadcast with both variants',
          cover: '/cover.jpg',
          video: '/full.mp4',
          videoStandard: '/smooth.mp4',
        },
        {
          id: '2106333329596809217',
          title: 'Clip with standard video only',
          cover: '/clip.jpg',
          video: '/clip.mp4',
        },
      ]),
    )

    const contents = await createProgrammeApi('/api', fetcher).contents('1', '2106333281679892481')

    expect(contents).toHaveLength(2)
    expect(contents[1]).toMatchObject({
      video: 'https://fscgc.scgchc.com/clip.mp4',
      smoothVideo: null,
    })
  })

  it('normalizes omitted covers and video variants to null while retaining valid records', async () => {
    const client = createProgrammeApi(
      '/api',
      vi.fn().mockResolvedValue(reply([{ id: '1', title: 'No video' }])),
    )

    expect(await client.contents('1', '2')).toEqual([
      {
        id: '1',
        title: 'No video',
        cover: null,
        video: null,
        smoothVideo: null,
        publishedAt: null,
      },
    ])
    expect(
      await createProgrammeApi(
        '/api',
        vi.fn().mockResolvedValue(reply({ records: [{ id: '1', name: 'No cover' }] })),
      ).programmes(),
    ).toEqual([{ id: '1', name: 'No cover', cover: null }])
  })
  it('rejects unsafe numeric IDs instead of silently rounding them', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValue(reply({ records: [{ id: Number('2107426129285414913'), name: '测试' }] }))
    await expect(createProgrammeApi('/api', fetcher).programmes()).rejects.toThrow('ID')
  })
  it('sorts and deduplicates valid dates; accepts an empty list', async () => {
    const fetcher = vi.fn().mockResolvedValue(
      reply([
        { id: '2', date: '2026-10-04' },
        { id: '3', date: '2026-10-06' },
        { id: '3', date: '2026-10-06' },
      ]),
    )
    expect((await createProgrammeApi('/api', fetcher).dates('1')).map((d) => d.date)).toEqual([
      '2026-10-06',
      '2026-10-04',
    ])
    expect(
      await createProgrammeApi('/api', vi.fn().mockResolvedValue(reply([]))).dates('1'),
    ).toEqual([])
  })
  it('rejects HTTP failures and malformed response shapes', async () => {
    await expect(
      createProgrammeApi(
        '/api',
        vi.fn().mockResolvedValue(new Response('', { status: 503 })),
      ).programmes(),
    ).rejects.toThrow('503')
    await expect(
      createProgrammeApi('/api', vi.fn().mockResolvedValue(reply({ records: null }))).programmes(),
    ).rejects.toThrow('数据')
  })
  it('resolves known URLs and rejects unsupported schemes', () => {
    expect(imageUrl('/covers/1.jpg')).toBe('https://kscgc.sctv.com/covers/1.jpg')
    expect(mediaUrl('javascript:alert(1)')).toBeNull()
  })

  it('rejects impossible calendar dates', async () => {
    const fetcher = vi.fn().mockResolvedValue(reply([{ id: '1', date: '2026-02-30' }]))
    await expect(createProgrammeApi('/api', fetcher).dates('1')).rejects.toThrow('日期')
  })
})
