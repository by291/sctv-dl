import { computed, onScopeDispose, ref, shallowRef } from 'vue'

import { programmeCacheKey, programmeSnapshotSchema } from '@shared/contracts/programme-cache'
import {
  receiveProgrammeSnapshot,
  acceptProgrammeUpdate,
} from '@/features/programmes/model/programme-snapshot-state'
import { LatestRequest } from '@/shared/utils/latest-request'
import { errorMessage } from '@/shared/utils/errors'

import type { ProgrammeCacheKey, ProgrammeSnapshot } from '@shared/contracts/programme-cache'
import type { ProgrammeSnapshotState } from '@/features/programmes/model/programme-snapshot-state'
import type { ProgrammeCachePort } from '@/shared/platform/ports'

type Snapshot<K> = Extract<ProgrammeSnapshot, { kind: K }>

export function useProgrammeSnapshot<K extends ProgrammeCacheKey['kind']>(
  kind: K,
  cache?: ProgrammeCachePort,
) {
  const state = shallowRef<ProgrammeSnapshotState<Snapshot<K>>>({ accepted: null, pending: null })
  const refreshing = ref(false)
  const failure = ref('')
  const cacheWarning = ref('')
  const cached = ref(false)
  const persisted = ref(false)
  const gate = new LatestRequest()
  let activeKey = ''
  let disposed = false
  let unsubscribe: (() => void) | undefined

  const accepted = computed(() => state.value.accepted)
  const pendingUpdate = computed(() => !!state.value.pending)
  const loading = computed(() => refreshing.value && !accepted.value)
  const error = computed(() => (accepted.value ? '' : failure.value))
  const refreshError = computed(() => (accepted.value ? failure.value : ''))
  const fetchedAt = computed(() => accepted.value?.fetchedAt ?? null)

  function matches(value: ProgrammeSnapshot): value is Snapshot<K> {
    return value.kind === kind
  }

  function reset() {
    gate.cancel()
    activeKey = ''
    state.value = { accepted: null, pending: null }
    failure.value = ''
    cached.value = false
    persisted.value = false
    refreshing.value = false
  }

  function clear() {
    gate.cancel()
    state.value = { accepted: accepted.value, pending: null }
    cacheWarning.value = accepted.value
      ? '缓存已清除，当前内容仅保留在页面中。'
      : '缓存已清除，请刷新获取节目内容。'
    cached.value = false
    persisted.value = false
    refreshing.value = false
  }

  const subscription = cache
    ?.subscribeCleared(clear)
    .then((stop) => {
      if (disposed) {
        stop()
      } else {
        unsubscribe = stop
      }
    })
    .catch((cause) => {
      if (!disposed) {
        cacheWarning.value = errorMessage(cause)
      }
    })

  async function load(
    key: Extract<ProgrammeCacheKey, { kind: K }>,
    fetcher: (signal: AbortSignal) => Promise<Snapshot<K>['items']>,
  ) {
    if (disposed) {
      return
    }

    const encoded = programmeCacheKey(key)
    if (activeKey !== encoded) {
      reset()
    }

    activeKey = encoded
    const request = gate.begin()
    refreshing.value = true
    failure.value = ''
    // Observe invalidation before any cache or live work can cross a clear boundary.
    if (subscription) {
      await subscription
    }

    if (!request.isCurrent()) {
      return
    }

    let networkReceived = false
    const cacheRead = cache
      ? cache
          .read(key)
          .then((result) => {
            if (!request.isCurrent()) {
              return null
            }

            cacheWarning.value = result.warning ?? ''
            const snapshot = result.snapshot
            if (
              !networkReceived &&
              snapshot &&
              matches(snapshot) &&
              programmeCacheKey(snapshot) === encoded &&
              !accepted.value
            ) {
              state.value = receiveProgrammeSnapshot(state.value, snapshot, 'cache')
              cached.value = true
              persisted.value = result.persisted
            }

            return result
          })
          .catch((cause) => {
            if (request.isCurrent()) {
              cacheWarning.value = errorMessage(cause)
            }

            return null
          })
      : Promise.resolve(null)

    try {
      const items = await fetcher(request.signal)
      if (!request.isCurrent()) {
        return
      }

      networkReceived = true
      const snapshot = programmeSnapshotSchema.parse({
        ...key,
        items,
        version: 1,
        revision: crypto.randomUUID(),
        fetchedAt: new Date().toISOString(),
      })
      if (!matches(snapshot)) {
        return
      }

      state.value = receiveProgrammeSnapshot(state.value, snapshot, 'network')
      if (!state.value.pending) {
        cached.value = false
      }

      refreshing.value = false

      // A late cache read supplies only the persistence epoch, never older presentation.
      const read = await cacheRead
      if (!request.isCurrent() || !cache || !read) {
        return
      }

      try {
        const result = await cache.write(snapshot, read.epoch)
        if (!request.isCurrent()) {
          return
        }

        persisted.value = result.persisted
        cacheWarning.value = result.warning ?? (result.persisted ? '' : '节目缓存仅在本次会话可用')
        if (result.accepted && result.snapshot && matches(result.snapshot)) {
          state.value = receiveProgrammeSnapshot(state.value, result.snapshot, 'network')
        } else if (!result.accepted) {
          clear()
        }
      } catch (cause) {
        if (request.isCurrent()) {
          persisted.value = false
          cacheWarning.value = errorMessage(cause)
        }
      }
    } catch (cause) {
      if (request.isCurrent()) {
        failure.value = errorMessage(cause)
      }

      await cacheRead
    } finally {
      if (request.isCurrent()) {
        refreshing.value = false
      }
    }
  }

  function acceptUpdate(held = false) {
    const previous = state.value
    state.value = acceptProgrammeUpdate(previous, held)
    if (state.value !== previous) {
      cached.value = false
    }
  }

  onScopeDispose(() => {
    disposed = true
    gate.cancel()
    unsubscribe?.()
  })

  return {
    accepted,
    pendingUpdate,
    loading,
    refreshing,
    cached,
    persisted,
    fetchedAt,
    error,
    refreshError,
    cacheWarning,
    load,
    reset,
    acceptUpdate,
  }
}
