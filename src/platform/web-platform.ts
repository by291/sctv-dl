import { createProgrammeApi } from '@/features/programmes/api/programme-api'
import { createWebPlayback } from '@/features/programmes/api/playback.web'
import { createWebDownloads } from '@/features/programmes/api/downloads.web'
import { createWebSettings } from '@/features/settings/api/settings.web'
import { createWebHistory } from '@/features/history/api/history.web'
import { createWebProgrammeCache } from '@/features/programmes/api/programme-cache.web'
import { createApplicationDatabase } from '@/shared/storage/application-database.web'

import type { AppPlatform } from '@/shared/platform/ports'

export function createWebPlatform(): AppPlatform {
  const base = import.meta.env.VITE_CLIENT_API_BASE || '/client-api/v1'
  const settings = createWebSettings()
  const database = createApplicationDatabase()
  const history = createWebHistory(database)
  const programmeCache = createWebProgrammeCache(database)

  return {
    kind: 'web',
    programmes: createProgrammeApi(base),
    playback: createWebPlayback(base),
    downloads: createWebDownloads(base),
    settings: settings.port,
    history: history.port,
    programmeCache: programmeCache.port,
    capabilities: { nativeDownloads: false, directorySelection: false },
    async dispose() {
      settings.dispose()
      history.dispose()
      programmeCache.dispose()
      database.dispose()
    },
  }
}
