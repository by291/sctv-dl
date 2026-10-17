import { computed, ref, watch } from 'vue'

import { isFullEpisode } from '@/features/programmes/model/full-episodes'
import { hasPlayableVideo } from '@/features/programmes/model/video-capabilities'

import type { Ref } from 'vue'
import type { ProgrammeContent } from '@/features/programmes/model/programme'

export function useContentSelection(
  contents: Ref<ProgrammeContent[]>,
  programmeName: Ref<string>,
  selectedDate: Ref<string | null>,
) {
  const selected = ref<string[]>([])

  const available = computed(() => contents.value.filter(hasPlayableVideo))
  const allSelected = computed(
    () =>
      available.value.length > 0 &&
      available.value.every((item) => selected.value.includes(item.id)),
  )

  const fullIds = computed(() =>
    contents.value
      .filter((item) => isFullEpisode(item.title, programmeName.value, selectedDate.value))
      .map((item) => item.id),
  )

  function selectAll(checked: boolean) {
    selected.value = checked ? available.value.map((item) => item.id) : []
  }

  function selectFullEpisodes() {
    selected.value = available.value
      .filter((item) => fullIds.value.includes(item.id))
      .map((item) => item.id)
  }

  watch(
    selectedDate,
    () => {
      selected.value = []
    },
    { flush: 'sync' },
  )

  watch(contents, () => {
    const ids = new Set(available.value.map((item) => item.id))
    selected.value = selected.value.filter((id) => ids.has(id))
  })

  return {
    selected,
    allSelected,
    fullIds,
    selectAll,
    selectFullEpisodes,
  }
}
