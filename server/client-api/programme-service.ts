import { randomUUID } from 'node:crypto'

import { makeDownloadFile } from '../programmes/download-file.ts'
import { getVideoVariants, resolveVideo } from '../programmes/video-variants.ts'
import { validateMediaTarget } from '../proxy/proxy-policy.ts'

import type { ProgrammeApi } from '../programmes/programme-client.ts'
import type { ContentRef } from '../../shared/contracts/programmes.ts'
import type { PlaybackRequest, PlaybackSession } from '../../shared/contracts/media.ts'
import type { DownloadRequest, PreparedDownloads } from '../../shared/contracts/downloads.ts'

export class ClientApiError extends Error {
  readonly status: number

  constructor(message: string, status = 400) {
    super(message)
    this.status = status
  }
}

export function createProgrammeService(client: ProgrammeApi, signal: AbortSignal) {
  async function broadcast(reference: Pick<ContentRef, 'programmeId' | 'dateId'>) {
    const dates = await client.dates(reference.programmeId, signal)
    const date = dates.find((item) => item.id === reference.dateId)
    if (!date) {
      throw new ClientApiError('播出日期已不可用，请刷新后重试', 404)
    }

    const contents = await client.contents(reference.programmeId, reference.dateId, signal)

    return { date: date.date, contents }
  }

  return {
    async playback(request: PlaybackRequest): Promise<PlaybackSession> {
      const { contents } = await broadcast(request)
      const content = contents.find((item) => item.id === request.contentId)
      const selected = content && resolveVideo(content, request.quality)
      if (!content || !selected) {
        throw new ClientApiError('这条内容没有可播放的视频', 404)
      }

      const sources = getVideoVariants(content).map((variant) => ({
        ...variant,
        url: validateMediaTarget(variant.url).href,
      }))
      const selectedQuality = sources.find((source) => source.url === selected.url)!.quality

      return { id: randomUUID(), selectedQuality, sources }
    },
    async downloads(request: DownloadRequest): Promise<PreparedDownloads> {
      const { date, contents } = await broadcast(request)
      const result: PreparedDownloads = { files: [], failures: [], usedFallback: false }

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
