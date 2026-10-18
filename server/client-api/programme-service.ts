import { randomUUID } from 'node:crypto'

import { makeDownloadFile } from '../programmes/download-file.ts'
import { getVideoVariants, resolveVideo } from '../programmes/video-variants.ts'
import { validateMediaTarget } from '../proxy/proxy-policy.ts'

import type { ProgrammeApi } from '../programmes/programme-client.ts'
import type { ContentRef, ProgrammeContent } from '../../shared/contracts/programmes.ts'
import type { PlaybackRequest, PlaybackSession } from '../../shared/contracts/media.ts'
import type { DownloadRequest, PreparedDownloads } from '../../shared/contracts/downloads.ts'

export class ProgrammeUnavailableError extends Error {
  readonly code = 'not-found'
}

export interface ProgrammeService {
  playback(request: PlaybackRequest): Promise<PlaybackSession>
  downloads(request: DownloadRequest): Promise<PreparedDownloads>
}

export function createProgrammeService(
  client: ProgrammeApi,
  signal: AbortSignal,
): ProgrammeService {
  async function loadBroadcast(
    reference: Pick<ContentRef, 'programmeId' | 'dateId'>,
  ): Promise<{ date: string; contents: ProgrammeContent[] }> {
    const dates = await client.dates(reference.programmeId, signal)
    const date = dates.find((item) => item.id === reference.dateId)
    if (!date) {
      throw new ProgrammeUnavailableError('播出日期已不可用，请刷新后重试')
    }

    const contents = await client.contents(reference.programmeId, reference.dateId, signal)

    return { date: date.date, contents }
  }

  return {
    async playback(request: PlaybackRequest): Promise<PlaybackSession> {
      const { contents } = await loadBroadcast(request)
      const content = contents.find((item) => item.id === request.contentId)
      const selected = content && resolveVideo(content, request.quality)
      const variants = content ? getVideoVariants(content) : []
      // Resolve against original variants before URL normalization; duplicate URLs retain one quality.
      const selectedVariant = variants.find((variant) => variant.url === selected?.url)
      if (!selectedVariant) {
        throw new ProgrammeUnavailableError('这条内容没有可播放的视频')
      }

      const sources = variants.map((variant) => ({
        ...variant,
        url: validateMediaTarget(variant.url).href,
      }))

      return { id: randomUUID(), selectedQuality: selectedVariant.quality, sources }
    },

    async downloads(request: DownloadRequest): Promise<PreparedDownloads> {
      const { date, contents } = await loadBroadcast(request)
      const result: PreparedDownloads = { files: [], failures: [], usedFallback: false }

      // One unavailable file must not discard other files prepared successfully in this batch.
      for (const contentId of request.contentIds) {
        try {
          const content = contents.find((item) => item.id === contentId)
          if (!content) {
            throw new Error('节目内容已不可用，请刷新后重试')
          }

          const file = makeDownloadFile(content, date, request.quality)
          validateMediaTarget(file.url)

          result.files.push(file)
          result.usedFallback ||= file.quality !== request.quality
        } catch (cause) {
          result.failures.push({
            contentId,
            message: cause instanceof Error ? cause.message : '无法准备下载',
          })
        }
      }

      return result
    },
  }
}
