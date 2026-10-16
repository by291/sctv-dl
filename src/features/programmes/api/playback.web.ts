import { playbackRequestSchema, playbackSessionSchema } from '@shared/contracts/media'

import { createClientApi } from '@/shared/platform/client-api'
import { proxyMediaUrl } from '@/shared/media/media-proxy-url'

import type { PlaybackPort } from '@/shared/platform/ports'

export function createWebPlayback(base?: string, fetcher?: typeof fetch): PlaybackPort {
  const request = createClientApi(base, fetcher)

  return {
    async open(input, signal) {
      const session = await request('/playback/prepare', playbackSessionSchema, {
        body: playbackRequestSchema.parse(input),
        signal,
      })

      return {
        ...session,
        sources: session.sources.map((source) => ({ ...source, url: proxyMediaUrl(source.url) })),
      }
    },
    async close() {
      // Web playback URLs own no server-side resources.
    },
  }
}
