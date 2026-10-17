import { onScopeDispose, ref, shallowRef, watch } from 'vue'
import { ZodError } from 'zod'
import { errorMessage } from '@/shared/utils/errors'
import type { Ref } from 'vue'
import type { ArchiveBrowseState } from '@shared/contracts/programme-cache'
import type { ProgrammeCachePort } from '@/shared/platform/ports'

type BrowsePosition = Pick<ArchiveBrowseState, 'dateId' | 'date' | 'sort' | 'scrollY'>

export function useArchiveBrowseState(programmeId: Ref<string>, cache: ProgrammeCachePort) {
  const saved = shallowRef<ArchiveBrowseState | null>(null)
  const warning = ref('')
  let epoch: string | null = null
  let generation = 0
  let disposed = false
  let ready = Promise.resolve()
  let unsubscribe: (() => void) | undefined

  function invalidate() {
    generation++
    epoch = null
    saved.value = null
  }

  const subscription = cache
    .subscribeCleared(invalidate)
    .then((stop) => {
      if (disposed) {
        stop()
      } else {
        unsubscribe = stop
      }
    })
    .catch((cause) => {
      if (!disposed) {
        warning.value = errorMessage(cause)
      }
    })

  watch(
    programmeId,
    (id) => {
      invalidate()
      const version = generation
      ready = subscription
        .then(async () => {
          if (disposed || version !== generation) {
            return
          }

          const result = await cache.readBrowseState(id)
          if (disposed || version !== generation) {
            return
          }

          epoch = result.epoch
          saved.value = result.value?.programmeId === id ? result.value : null
          warning.value = result.warning ?? ''
        })
        .catch((cause) => {
          if (!disposed && version === generation) {
            warning.value = errorMessage(cause)
          }
        })
    },
    { immediate: true, flush: 'sync' },
  )

  async function save(value: BrowsePosition) {
    if (disposed || !epoch) {
      return
    }

    const version = generation
    // Start the write before the caller tears down the route. Clear still fences its epoch.
    try {
      const result = await cache.writeBrowseState(
        { ...value, programmeId: programmeId.value, visitedAt: new Date().toISOString() },
        epoch,
      )
      if (!disposed && version === generation && result.accepted) {
        warning.value = result.persisted ? '' : '浏览位置仅在本次会话可用'
      }
    } catch (cause) {
      if (!disposed && version === generation) {
        warning.value = cause instanceof ZodError ? '浏览位置暂时无法保存' : errorMessage(cause)
      }
    }
  }

  function dispose() {
    if (disposed) {
      return
    }

    disposed = true
    generation++
    unsubscribe?.()
  }

  onScopeDispose(dispose)

  return {
    get ready() {
      return ready
    },
    saved,
    warning,
    save,
    dispose,
  }
}
