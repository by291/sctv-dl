import { ref } from 'vue'

import { handOffDownload } from '@/shared/media/browser-download'
import { makeDownloadFile } from '@/features/programmes/model/download-file'
import { errorMessage } from '@/shared/utils/errors'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'

export interface DownloadBatchResult {
  handedOff: number
  usedFallback: boolean
  failures: string[]
}

export function useProgrammeDownloads() {
  const preparingIds = ref<string[]>([])

  async function prepareDownloads(
    items: ProgrammeContent[],
    date: string,
    quality: Quality,
  ): Promise<DownloadBatchResult | null> {
    if (!items.length || preparingIds.value.length) {
      return null
    }

    preparingIds.value = items.map((item) => item.id)

    try {
      const files = items.map((item) => makeDownloadFile(item, date, quality))
      const result: DownloadBatchResult = { handedOff: 0, usedFallback: false, failures: [] }

      // Await preparation only; the browser owns transfer progress and completion.
      for (const file of files) {
        try {
          await handOffDownload(file)
          result.handedOff += 1
          result.usedFallback ||= file.quality !== quality
        } catch (cause) {
          result.failures.push(`${file.title}：${errorMessage(cause)}`)
        }
      }

      return result
    } finally {
      preparingIds.value = []
    }
  }

  return { preparingIds, prepareDownloads }
}
