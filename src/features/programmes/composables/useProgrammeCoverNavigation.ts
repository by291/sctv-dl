import { computed, onScopeDispose, ref, toValue } from 'vue'
import { useRouter } from 'vue-router'

import { canStartViewTransition, runViewTransition } from '@/shared/utils/view-transition'
import { navigationTab } from '@/shared/navigation/navigation-tab'

import type { MaybeRefOrGetter } from 'vue'

export function useProgrammeCoverNavigation(programmeId: MaybeRefOrGetter<string>) {
  const router = useRouter()
  const selected = ref(false)
  const coverStyle = computed(() => ({
    viewTransitionName: selected.value ? 'programme-cover' : 'none',
  }))
  let stopReturnNavigation: (() => void) | undefined
  let disposed = false

  function rememberReturn(id: string, sourcePath: string, detailPath: string): void {
    stopReturnNavigation?.()

    if (disposed) {
      return
    }

    const removeGuard = router.beforeResolve((to, from) => {
      if (
        from.path !== detailPath ||
        to.path !== sourcePath ||
        toValue(programmeId) !== id ||
        !canStartViewTransition()
      ) {
        return
      }

      const origin = router.currentRoute.value
      let superseded = false
      let continueNavigation: (allowed: boolean) => void = () => {}

      let finishNavigation: (updated: boolean) => void = () => {}

      const allowed = new Promise<boolean>((resolve) => {
        continueNavigation = resolve
      })
      const navigated = new Promise<boolean>((resolve) => {
        finishNavigation = resolve
      })
      const stopWatching = router.beforeEach(() => {
        superseded = true
      })
      const stopAfter = router.afterEach((destination, _from, failure) => {
        if (destination === to) {
          finishNavigation(!failure && router.currentRoute.value.path === sourcePath)
        }
      })
      const stopError = router.onError((_error, destination) => {
        if (destination === to) {
          finishNavigation(false)
        }
      })
      selected.value = true

      // Release this existing navigation inside capture, preserving browser history.
      void runViewTransition(async () => {
        stopWatching()

        if (superseded || router.currentRoute.value !== origin) {
          continueNavigation(false)

          return false
        }

        continueNavigation(true)

        const updated = await navigated

        return updated && !disposed && toValue(programmeId) === id
      })
        .catch(() => {})
        .finally(() => {
          continueNavigation(false)
          stopWatching()
          stopAfter()
          stopError()
          selected.value = false
        })

      return allowed
    })
    const removeAfter = router.afterEach((to, _from, failure) => {
      // Another primary tab only hides this detail. Release the association when
      // navigation in its own tab replaces it, including a home link from another tab.
      if (
        !failure &&
        navigationTab(to.path) === navigationTab(detailPath) &&
        to.path !== detailPath
      ) {
        stopReturnNavigation?.()
      }
    })
    stopReturnNavigation = () => {
      removeGuard()
      removeAfter()
      stopReturnNavigation = undefined
    }
  }

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
      const updated = !failure && router.currentRoute.value.path === path

      if (updated) {
        rememberReturn(id, origin.path, path)
      }

      return updated
    })
      .catch(() => {})
      .finally(() => {
        stopWatching()
        selected.value = false
      })
  }

  onScopeDispose(() => {
    disposed = true
    stopReturnNavigation?.()
  })

  return { coverStyle, openProgramme }
}
