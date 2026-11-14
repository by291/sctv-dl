import { nextTick, readonly, ref } from 'vue'

const active = ref(false)

export const viewTransitionActive = readonly(active)

// Check browser support, motion preference, and transition ownership.
export function canStartViewTransition(): boolean {
  return (
    !active.value &&
    typeof document.startViewTransition === 'function' &&
    !window.matchMedia('(prefers-reduced-motion: reduce)').matches
  )
}

// Run one navigation update and release transition state when it settles.
export async function runViewTransition(update: () => Promise<boolean | void>): Promise<void> {
  active.value = true
  await nextTick()

  let updateStarted = false
  let transition: ViewTransition | undefined
  const renderUpdate = async () => {
    updateStarted = true
    const updated = await update()
    await nextTick()

    if (updated === false) {
      transition?.skipTransition()
    }
  }

  try {
    try {
      transition = document.startViewTransition(renderUpdate)
    } catch (error) {
      active.value = false

      // Once the callback has started, running it again could navigate twice.
      if (updateStarted) {
        throw error
      }

      await renderUpdate()

      return
    }

    // A skipped capture must not turn a successful navigation into an unhandled rejection.
    void transition.ready.catch(() => {})

    try {
      await transition.updateCallbackDone
    } finally {
      await transition.finished.catch(() => {})
    }
  } finally {
    active.value = false
  }
}
