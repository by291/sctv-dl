import { computed, ref, watch } from 'vue'

import { resolveVideo } from '../video'

import type { Ref } from 'vue'
import type { ProgrammeContent } from '../types'

export function useContentSelection(
  contents: Ref<ProgrammeContent[]>,
  programmeName: Ref<string>,
  selectedDate: Ref<string | null>,
) {
  const selected = ref<string[]>([])

  const hasVideo = (content: ProgrammeContent) => !!resolveVideo(content, 'standard')
  const available = computed(() => contents.value.filter(hasVideo))
  const allSelected = computed(
    () =>
      available.value.length > 0 &&
      available.value.every((item) => selected.value.includes(item.id)),
  )

  const fullIds = computed(() => {
    if (!programmeName.value || !selectedDate.value) {
      return []
    }

    const date = selectedDate.value.replaceAll('-', '.')
    const titles = [`${programmeName.value}（${date}）`, `${programmeName.value}(${date})`]

    // Match the programme name and date explicitly; the first item is not necessarily a full episode.
    return contents.value
      .filter((item) => titles.includes(item.title.replace(/\s/g, '')))
      .map((item) => item.id)
  })

  function selectAll(checked: boolean) {
    selected.value = checked ? available.value.map((item) => item.id) : []
  }

  function selectFullEpisodes() {
    selected.value = available.value
      .filter((item) => fullIds.value.includes(item.id))
      .map((item) => item.id)
  }

  watch(contents, () => {
    selected.value = []
  })

  return {
    selected,
    allSelected,
    fullIds,
    hasVideo,
    selectAll,
    selectFullEpisodes,
  }
}
