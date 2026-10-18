import { inject } from 'vue'
import type { InjectionKey } from 'vue'
import type { ScrollPosition } from '@/shared/navigation/scroll-restoration'

export const pageScrollTargetKey: InjectionKey<() => HTMLElement | null> =
  Symbol('page-scroll-target')

// Async page work remains scoped to its own tab, including while it is cached offscreen.
export function usePageScroll() {
  const ownTarget = inject(pageScrollTargetKey, null)
  const target = () => (ownTarget ? ownTarget() : pageScrollTarget())

  return {
    pageScrollTarget: target,
    pageScrollPosition: () => {
      const element = target()

      return element ? pageScrollPosition(element) : { left: 0, top: 0 }
    },
    pageScrollMaximum: () => {
      const element = target()

      return element ? pageScrollMaximum(element) : 0
    },
    scrollPageTo: (position: ScrollToOptions) => {
      const element = target()
      if (element) {
        scrollPageTo(position, element)
      }
    },
  }
}

// The shell owns scrolling. The window fallback supports standalone pages before it mounts.
export function pageScrollTarget(): HTMLElement | Window {
  return document.getElementById('workspace-scroll') ?? window
}

export function pageScrollPosition(
  target: HTMLElement | Window = pageScrollTarget(),
): ScrollPosition {
  // WebKit reports negative offsets during edge bounce; do not save that transient geometry.
  return target instanceof HTMLElement
    ? { left: Math.max(0, target.scrollLeft), top: Math.max(0, target.scrollTop) }
    : { left: Math.max(0, target.scrollX), top: Math.max(0, target.scrollY) }
}

export function pageScrollMaximum(target: HTMLElement | Window = pageScrollTarget()): number {
  return Math.max(
    0,
    target instanceof HTMLElement
      ? target.scrollHeight - target.clientHeight
      : document.documentElement.scrollHeight - window.innerHeight,
  )
}

export function scrollPageTo(
  position: ScrollToOptions,
  target: HTMLElement | Window = pageScrollTarget(),
): void {
  target.scrollTo({ ...position, behavior: position.behavior ?? 'instant' })
}
