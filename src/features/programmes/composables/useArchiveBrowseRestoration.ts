import {
  inject,
  nextTick,
  onActivated,
  onBeforeUnmount,
  onDeactivated,
  onMounted,
  ref,
  watch,
} from 'vue'
import { onBeforeRouteLeave, useRoute } from 'vue-router'
import { useEventListener, useThrottleFn } from '@vueuse/core'

import {
  createScrollRestoration,
  scrollRestorationKey,
} from '@/shared/navigation/scroll-restoration'
import { usePageScroll } from '@/shared/navigation/page-scroll'

import type { Ref } from 'vue'
import type { useArchiveBrowseState } from '@/features/programmes/composables/useArchiveBrowseState'
import type { ContentSortOrder } from '@/features/programmes/model/content-presentation'

interface ArchiveBrowseRestorationOptions {
  programmeId: Readonly<Ref<string>>
  browse: ReturnType<typeof useArchiveBrowseState>
  datesLoaded: Readonly<Ref<boolean>>
  contentsLoaded: Readonly<Ref<boolean>>
  selectedDateId: Readonly<Ref<string>>
  selectedDate: Readonly<Ref<string | null>>
}

export function useArchiveBrowseRestoration({
  programmeId,
  browse,
  datesLoaded,
  contentsLoaded,
  selectedDateId,
  selectedDate,
}: ArchiveBrowseRestorationOptions) {
  const route = useRoute()
  const { pageScrollMaximum, pageScrollPosition, pageScrollTarget, scrollPageTo } = usePageScroll()
  const restoration = inject(scrollRestorationKey, null) ?? createScrollRestoration()
  const contentSortOrder = ref<ContentSortOrder>('asc')
  let scrollEntry = restoration.begin(route.fullPath)
  let scrollFrame: number | undefined
  let departed = false
  let disposed = false
  let scrollSettled = false
  let activated = false

  function saveBrowse() {
    if (!datesLoaded.value || departed || disposed) {
      return
    }

    void browse.save({
      dateId: selectedDateId.value || null,
      date: selectedDate.value,
      sort: contentSortOrder.value,
      // Date hydration finishes before content layout; keep the saved offset until restoration.
      scrollY: scrollSettled
        ? pageScrollPosition().top
        : (browse.saved.value?.scrollY ?? pageScrollPosition().top),
    })
  }

  async function restoreAfterContentRender() {
    if (!datesLoaded.value || (selectedDate.value && !contentsLoaded.value)) {
      return
    }

    const entry = scrollEntry
    const id = programmeId.value
    await browse.ready
    await nextTick()
    if (disposed || departed || id !== programmeId.value) {
      return
    }

    if (scrollFrame !== undefined) {
      cancelAnimationFrame(scrollFrame)
    }

    scrollFrame = requestAnimationFrame(() => {
      if (disposed || departed || id !== programmeId.value || entry !== scrollEntry) {
        return
      }

      entry.restore(browse.saved.value?.scrollY ?? 0)
      scrollSettled = true
      saveBrowse()
    })
  }

  async function preserveScrollAfter(update: () => Promise<void>) {
    const { top } = pageScrollPosition()
    await update()
    await nextTick()
    scrollPageTo({ top: Math.min(top, pageScrollMaximum()) })
  }

  watch(
    browse.saved,
    (saved) => {
      // Clearing persistence must not reorder a currently visible archive.
      if (saved) {
        contentSortOrder.value = saved.sort
      }
    },
    { flush: 'sync' },
  )
  watch([datesLoaded, selectedDateId, selectedDate, contentSortOrder], saveBrowse, {
    flush: 'post',
  })
  watch(programmeId, () => {
    scrollSettled = false
    scrollEntry.cancel()
    scrollEntry = restoration.begin(route.fullPath)
    departed = false
  })
  watch([datesLoaded, contentsLoaded, selectedDate], restoreAfterContentRender, { flush: 'post' })

  // Leading-only throttling has no trailing timer to outlive the route; scrollend captures the tail.
  const saveScroll = useThrottleFn(saveBrowse, 1000, false, true)
  useEventListener(document, 'visibilitychange', () => {
    if (document.hidden) {
      saveBrowse()
    }
  })
  useEventListener(window, 'pagehide', saveBrowse)

  onBeforeRouteLeave(() => {
    saveBrowse()
    departed = true
    scrollEntry.cancel()
  })
  onBeforeUnmount(() => {
    if (!departed) {
      saveBrowse()
    }

    disposed = true
    scrollEntry.cancel()
    if (scrollFrame !== undefined) {
      cancelAnimationFrame(scrollFrame)
    }
  })

  onActivated(() => {
    departed = false
    // A returning tab owns its live offset, even if loading finished while it was hidden.
    if (activated) {
      scrollSettled = true
    }

    activated = true
  })
  onDeactivated(() => {
    departed = true
  })
  onMounted(() => {
    useEventListener(pageScrollTarget(), 'scroll', saveScroll, { passive: true })
    useEventListener(pageScrollTarget(), 'scrollend', saveBrowse)
  })

  return { contentSortOrder, preserveScrollAfter }
}
