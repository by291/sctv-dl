import { ref } from 'vue'

import { usePlatform } from '@/shared/platform/usePlatform'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'
import type { DownloadStartResult } from '@shared/contracts/downloads'

export function useProgrammeDownloads() {
  const downloads = usePlatform().downloads
  const tasks = downloads.kind === 'native' ? useDownloadTasksStore() : undefined
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
      const request = {
        programmeId,
        dateId,
        contentIds: items.map((item) => item.id),
        quality,
      }

      return downloads.kind === 'native' && tasks
        ? await tasks.start(request, downloads)
        : await downloads.start(request)
    } finally {
      preparingIds.value = []
    }
  }

  return { preparingIds, prepareDownloads }
}
