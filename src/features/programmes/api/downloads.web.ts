import { downloadRequestSchema, preparedDownloadsSchema } from '@shared/contracts/downloads'

import { createClientApi } from '@/shared/platform/client-api'
import { handOffDownload } from '@/shared/media/browser-download'
import { errorMessage } from '@/shared/utils/errors'

import type { BrowserDownloadPort } from '@/shared/platform/ports'

export function createWebDownloads(base?: string, fetcher?: typeof fetch): BrowserDownloadPort {
  const request = createClientApi(base, fetcher)

  return {
    kind: 'browser',
    async start(input) {
      const prepared = await request('/downloads/prepare', preparedDownloadsSchema, {
        body: downloadRequestSchema.parse(input),
      })
      const result = {
        kind: 'browser' as const,
        handedOff: 0,
        usedFallback: false,
        failures: [...prepared.failures],
      }

      for (const file of prepared.files) {
        try {
          await handOffDownload(file, fetcher)
          result.handedOff += 1
          result.usedFallback ||= file.quality !== input.quality
        } catch (cause) {
          result.failures.push({
            contentId: file.contentId,
            message: `${file.title}：${errorMessage(cause)}`,
          })
        }
      }

      return result
    },
  }
}
