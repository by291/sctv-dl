import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

import { usePlatform } from '@/shared/platform/usePlatform'
import { useProgrammeSnapshot } from '@/features/programmes/composables/useProgrammeSnapshot'

import type { Programme } from '@/features/programmes/model/programme'

export const useProgrammeCatalogueStore = defineStore('programmes', () => {
  const platform = usePlatform()
  const snapshots = useProgrammeSnapshot('catalogue', platform.programmeCache)
  const programmes = ref<Programme[]>([])
  const updatedAt = ref<Date | null>(null)
  const error = ref('')
  watch(
    snapshots.fetchedAt,
    (value) => {
      updatedAt.value = value ? new Date(value) : null
    },
    { flush: 'sync' },
  )
  watch(
    snapshots.error,
    (value) => {
      error.value = value
    },
    { flush: 'sync' },
  )
  watch(
    snapshots.accepted,
    (snapshot) => {
      if (snapshot) {
        programmes.value = snapshot.items
      }
    },
    { flush: 'sync' },
  )

  async function load(force = false) {
    if (
      !force &&
      (snapshots.accepted.value || programmes.value.length || snapshots.refreshing.value)
    ) {
      return
    }

    await snapshots.load({ kind: 'catalogue' }, (signal) => platform.programmes.programmes(signal))
  }

  async function acceptUpdate() {
    snapshots.acceptUpdate()
  }

  return {
    programmes,
    loading: snapshots.loading,
    refreshing: snapshots.refreshing,
    error,
    updatedAt,
    load,
    acceptUpdate,
    pendingUpdate: snapshots.pendingUpdate,
    cached: snapshots.cached,
    fetchedAt: snapshots.fetchedAt,
    refreshError: snapshots.refreshError,
    cacheWarning: snapshots.cacheWarning,
  }
})
