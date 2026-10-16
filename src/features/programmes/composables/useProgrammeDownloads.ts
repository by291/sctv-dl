import { ref } from 'vue'

import { usePlatform } from '@/shared/platform/usePlatform'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'
import type { DownloadStartResult } from '@shared/contracts/downloads'

export function useProgrammeDownloads() {
  const downloads = usePlatform().downloads
  const preparingIds = ref<string[]>([])

  async function prepareDownloads(
    items: ProgrammeContent[],
    dateId: string,
    quality: Quality,
    programmeId: string,
  ): Promise<DownloadStartResult | null> {
    if (!items.length || !dateId || preparingIds.value.length) {
      return null
    }

    preparingIds.value = items.map((item) => item.id)
    try {
      return await downloads.start({
        programmeId,
        dateId,
        contentIds: items.map((item) => item.id),
        quality,
      })
    } finally {
      preparingIds.value = []
    }
  }

  return { preparingIds, prepareDownloads }
}
