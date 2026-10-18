import { defineStore } from 'pinia'
import { computed } from 'vue'

import { usePlatform } from '@/shared/platform/usePlatform'
import { useProgrammeSnapshot } from '@/features/programmes/composables/useProgrammeSnapshot'
import { programmeServiceStatus } from '@/features/programmes/model/programme-service-status'

export const useProgrammeCatalogueStore = defineStore('programmes', () => {
  const platform = usePlatform()
  const snapshots = useProgrammeSnapshot('catalogue', platform.programmeCache)
  const programmes = computed(() => snapshots.accepted.value?.items ?? [])
  const updatedAt = computed(() =>
    snapshots.fetchedAt.value ? new Date(snapshots.fetchedAt.value) : null,
  )
  const serviceStatus = computed(() =>
    programmeServiceStatus({
      error: snapshots.error.value,
      refreshError: snapshots.refreshError.value,
      refreshing: snapshots.refreshing.value,
      cached: snapshots.cached.value,
      fetchedAt: snapshots.fetchedAt.value,
    }),
  )

  async function load(force = false) {
    if (!force && (snapshots.accepted.value || snapshots.refreshing.value)) {
      return
    }

    await snapshots.load({ kind: 'catalogue' }, (signal) => platform.programmes.programmes(signal))
  }

  function acceptUpdate() {
    snapshots.acceptUpdate()
  }

  return {
    programmes,
    loading: snapshots.loading,
    refreshing: snapshots.refreshing,
    error: snapshots.error,
    updatedAt,
    serviceStatus,
    load,
    acceptUpdate,
    pendingUpdate: snapshots.pendingUpdate,
    cached: snapshots.cached,
    fetchedAt: snapshots.fetchedAt,
    refreshError: snapshots.refreshError,
    cacheWarning: snapshots.cacheWarning,
  }
})
