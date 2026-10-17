import { createTauriProgrammeApi } from '@/features/programmes/api/programme-api.tauri'
import { createTauriPlayback } from '@/features/programmes/api/playback.tauri'
import { createTauriDownloads } from '@/features/programmes/api/downloads.tauri'
import { createTauriSettings } from '@/features/settings/api/settings.tauri'
import { createTauriHistory } from '@/features/history/api/history.tauri'
import { createTauriProgrammeCache } from '@/features/programmes/api/programme-cache.tauri'

import { prepareNativeExit } from '@/platform/exit.tauri'

import type { AppPlatform } from '@/shared/platform/ports'

export function createTauriPlatform(): AppPlatform {
  const playback = createTauriPlayback()
  const history = createTauriHistory()
  const programmeCache = createTauriProgrammeCache()

  return {
    kind: 'tauri',
    programmes: createTauriProgrammeApi(),
    playback,
    downloads: createTauriDownloads(),
    settings: createTauriSettings(),
    history: history.port,
    programmeCache: programmeCache.port,
    capabilities: { nativeDownloads: true, directorySelection: true },
    prepareExit: prepareNativeExit,
    async dispose() {
      await playback.dispose()
      await history.dispose()
      programmeCache.dispose()
    },
  }
}
