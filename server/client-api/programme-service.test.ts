import { describe, expect, it } from 'vitest'

import { createProgrammeService } from './programme-service.ts'

import type { ProgrammeApi } from '../programmes/programme-client.ts'
import type { ProgrammeContent } from '../../shared/contracts/programmes.ts'

const content: ProgrammeContent = {
  id: '3',
  title: 'News',
  cover: null,
  video: 'https://fscgc.scgchc.com/news.mp4',
  smoothVideo: null,
  publishedAt: null,
}
const reference = { programmeId: '1', dateId: '2', contentId: '3' }

function programmeClient(contents: ProgrammeContent[]): ProgrammeApi {
  return {
    async programmes() {
      return []
    },
    async dates() {
      return [{ id: '2', date: '2026-10-16' }]
    },
    async contents() {
      return contents
    },
  }
}

describe('programme preparation service', () => {
  it.each(['fscgc.scgchc.com', 'fscgc.sctv-tf.com'])(
    'prepares playback and downloads from %s',
    async (host) => {
      const url = `https://${host}/NewsTV/2021/02/09/archive.mp4`
      const service = createProgrammeService(
        programmeClient([{ ...content, video: url }]),
        new AbortController().signal,
      )

      const playback = await service.playback({ ...reference, quality: 'standard' })
      const downloads = await service.downloads({
        programmeId: '1',
        dateId: '2',
        contentIds: ['3'],
        quality: 'standard',
      })

      expect(playback.sources).toEqual([{ quality: 'standard', url }])
      expect(downloads.files).toMatchObject([{ contentId: '3', quality: 'standard', url }])
      expect(downloads.failures).toEqual([])
    },
  )

  it('uses the available smooth source when the requested standard source is missing', async () => {
    const service = createProgrammeService(
      programmeClient([{ ...content, video: null, smoothVideo: content.video }]),
      new AbortController().signal,
    )

    const session = await service.playback({ ...reference, quality: 'standard' })

    expect(session.id).not.toBe('')
    expect(session.selectedQuality).toBe('smooth')
    expect(session.sources).toEqual([
      { quality: 'smooth', url: 'https://fscgc.scgchc.com/news.mp4' },
    ])
  })

  it('selects the retained quality when both upstream fields point to the same video', async () => {
    const service = createProgrammeService(
      programmeClient([{ ...content, smoothVideo: content.video }]),
      new AbortController().signal,
    )

    const session = await service.playback({ ...reference, quality: 'smooth' })

    expect(session.selectedQuality).toBe('standard')
    expect(session.sources).toEqual([
      { quality: 'standard', url: 'https://fscgc.scgchc.com/news.mp4' },
    ])
  })

  it('keeps source selection associated with the variant while normalizing its URL', async () => {
    const service = createProgrammeService(
      programmeClient([{ ...content, video: 'https://FSCGC.scgchc.com/news.mp4' }]),
      new AbortController().signal,
    )

    const session = await service.playback({ ...reference, quality: 'standard' })

    expect(session.selectedQuality).toBe('standard')
    expect(session.sources).toEqual([
      { quality: 'standard', url: 'https://fscgc.scgchc.com/news.mp4' },
    ])
  })

  it('reports a missing broadcast with a business code independent of HTTP status', async () => {
    const service = createProgrammeService(programmeClient([]), new AbortController().signal)

    await expect(
      service.playback({ ...reference, dateId: '99', quality: 'standard' }),
    ).rejects.toMatchObject({ code: 'not-found' })
  })

  it('rejects playback sources outside the verified media CDN', async () => {
    const service = createProgrammeService(
      programmeClient([{ ...content, video: 'https://example.com/news.mp4' }]),
      new AbortController().signal,
    )

    await expect(service.playback({ ...reference, quality: 'standard' })).rejects.toThrow()
  })

  it('retains valid downloads while reporting missing, unavailable, and forbidden files', async () => {
    const service = createProgrammeService(
      programmeClient([
        content,
        { ...content, id: '5', video: null },
        { ...content, id: '6', video: 'https://example.com/news.mp4' },
      ]),
      new AbortController().signal,
    )

    const result = await service.downloads({
      programmeId: '1',
      dateId: '2',
      contentIds: ['4', '3', '5', '6'],
      quality: 'smooth',
    })

    expect(result.files).toEqual([
      {
        contentId: '3',
        title: 'News',
        url: 'https://fscgc.scgchc.com/news.mp4',
        filename: '2026-10-16_News_标准.mp4',
        quality: 'standard',
      },
    ])
    expect(result.failures.map((failure) => failure.contentId)).toEqual(['4', '5', '6'])
    expect(result.usedFallback).toBe(true)
  })
})
