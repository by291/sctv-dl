import { onDeactivated, ref, shallowRef } from 'vue'

import type { HistoryEntry } from '@shared/contracts/history'
import type { ProgrammeContent } from '@shared/contracts/programmes'
import type { PreviewInput } from '@/features/programmes/model/playback-state'

export function useHistoryPreview() {
  const content = ref<ProgrammeContent | null>(null)
  const input = shallowRef<PreviewInput | null>(null)

  function open(entry: HistoryEntry): void {
    // Playback resolves fresh sources from these saved IDs, so viewing history
    // remains usable before the catalogue loads and never trusts an expired URL.
    content.value = {
      id: entry.content.contentId,
      title: entry.title,
      cover: entry.cover,
      video: null,
      smoothVideo: null,
      publishedAt: null,
    }
    input.value = {
      kind: 'online',
      metadata: {
        content: { ...entry.content },
        programmeName: entry.programmeName,
        broadcastDate: entry.broadcastDate,
        title: entry.title,
        cover: entry.cover,
      },
      content: content.value,
    }
  }

  onDeactivated(() => {
    content.value = null
  })

  return { content, input, open }
}
