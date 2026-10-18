import type { InjectionKey } from 'vue'
import { pageScrollMaximum, scrollPageTo } from '@/shared/navigation/page-scroll'

export interface ScrollPosition {
  left: number
  top: number
}

export interface ScrollRestoration {
  scrollOnEnter(routeKey: string, position: ScrollPosition, mode?: 'navigation' | 'history'): void
  pageEntered(routeKey: string, retainedPosition?: ScrollPosition): void
  captureSavedPosition(routeKey: string, position: ScrollPosition | null): void
  takeSavedPosition(routeKey: string): ScrollPosition | null
  begin(routeKey: string): { restore(fallback: number): boolean; cancel(): void }
  cancel(): void
}

export const scrollRestorationKey: InjectionKey<ScrollRestoration> = Symbol('scroll-restoration')

export function createScrollRestoration(): ScrollRestoration {
  const positions = new Map<string, ScrollPosition>()
  let cancelActive = () => {}

  let entered: { key: string; retainedPosition?: ScrollPosition } | null = null
  let pending: { key: string; position: ScrollPosition; mode: 'navigation' | 'history' } | null =
    null

  function applyPending() {
    if (pending && entered?.key === pending.key) {
      scrollPageTo(
        pending.mode === 'history'
          ? pending.position
          : (entered.retainedPosition ?? pending.position),
      )
      pending = null
    }
  }

  function takeSavedPosition(key: string) {
    const position = positions.get(key) ?? null
    positions.delete(key)

    return position
  }

  function begin(key: string) {
    cancelActive()
    let active = true

    function cancel() {
      active = false
      window.removeEventListener('wheel', cancel)
      window.removeEventListener('touchstart', cancel)
      window.removeEventListener('keydown', keydown)
    }

    function keydown(event: KeyboardEvent) {
      if (['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp', 'Home', 'End', ' '].includes(event.key)) {
        cancel()
      }
    }

    window.addEventListener('wheel', cancel, { passive: true })
    window.addEventListener('touchstart', cancel, { passive: true })
    window.addEventListener('keydown', keydown)
    cancelActive = cancel

    function restore(fallback: number) {
      if (!active) {
        return false
      }

      const position = takeSavedPosition(key) ?? { left: 0, top: fallback }
      const maximum = pageScrollMaximum()
      scrollPageTo({
        left: position.left,
        top: Math.min(Math.max(0, position.top), maximum),
        behavior: 'instant',
      })
      cancel()

      return true
    }

    return { restore, cancel }
  }

  return {
    scrollOnEnter(key, position, mode = 'navigation') {
      pending = { key, position, mode }
      applyPending()
    },
    pageEntered(key, retainedPosition) {
      entered = { key, retainedPosition }
      applyPending()
    },
    begin,
    takeSavedPosition,
    captureSavedPosition(key, position) {
      if (position) {
        positions.set(key, position)
      } else {
        positions.delete(key)
      }
    },
    cancel() {
      cancelActive()
      positions.clear()
      entered = null
      pending = null
    },
  }
}
