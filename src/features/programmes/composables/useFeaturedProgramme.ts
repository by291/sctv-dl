import { computed, ref, watch } from 'vue'

import type { Ref } from 'vue'
import type { Programme } from '@/features/programmes/model/programme'

export function useFeaturedProgramme(
  programmes: Ref<Programme[]>,
  random: () => number = Math.random,
) {
  const featuredId = ref<string | null>(null)
  const featured = computed(
    () => programmes.value.find((programme) => programme.id === featuredId.value) ?? null,
  )
  const canChange = computed(() => programmes.value.length > 1)

  function chooseAnother() {
    const alternatives = programmes.value.filter((programme) => programme.id !== featuredId.value)
    const candidates = alternatives.length ? alternatives : programmes.value

    featuredId.value = candidates[Math.floor(random() * candidates.length)]?.id ?? null
  }

  watch(
    programmes,
    (catalogue) => {
      // Preserve the choice on refresh unless the programme has been removed.
      if (!catalogue.some((programme) => programme.id === featuredId.value)) {
        chooseAnother()
      }
    },
    { immediate: true },
  )

  return {
    featured,
    canChange,
    chooseAnother,
  }
}
