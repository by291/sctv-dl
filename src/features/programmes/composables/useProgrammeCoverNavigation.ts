import { computed, ref, toValue } from 'vue'
import { useRouter } from 'vue-router'

import { canStartViewTransition, runViewTransition } from '../../../shared/view-transition'

import type { MaybeRefOrGetter } from 'vue'

export function useProgrammeCoverNavigation(programmeId: MaybeRefOrGetter<string>) {
  const router = useRouter()
  const selected = ref(false)
  const coverStyle = computed(() => ({
    viewTransitionName: selected.value ? 'programme-cover' : 'none',
  }))

  function openProgramme(event: MouseEvent): void {
    const link = event.currentTarget

    if (
      event.defaultPrevented ||
      event.button !== 0 ||
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey ||
      event.altKey ||
      (link instanceof HTMLAnchorElement && link.target && link.target !== '_self') ||
      !canStartViewTransition()
    ) {
      return
    }

    event.preventDefault()
    const id = toValue(programmeId)
    const origin = router.currentRoute.value
    let superseded = false
    const stopWatching = router.beforeEach(() => {
      superseded = true
    })
    selected.value = true

    void runViewTransition(async () => {
      stopWatching()

      // Native capture can defer this callback beyond a newer link activation.
      if (superseded || router.currentRoute.value !== origin) {
        return false
      }

      const path = `/programmes/${id}`
      const failure = await router.push(path)

      return !failure && router.currentRoute.value.path === path
    })
      .catch(() => {})
      .finally(() => {
        stopWatching()
        selected.value = false
      })
  }

  return { coverStyle, openProgramme }
}
