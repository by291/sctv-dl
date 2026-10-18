import { computed, nextTick, onScopeDispose, ref, watch } from 'vue'

import { usePlatform } from '@/shared/platform/usePlatform'
import { useProgrammeSnapshot } from '@/features/programmes/composables/useProgrammeSnapshot'

import type { Ref } from 'vue'
import type { ProgrammeApi, ProgrammeCachePort } from '@/shared/platform/ports'
import type { ArchiveBrowseState } from '@shared/contracts/programme-cache'
import type { ProgrammeDate } from '@/features/programmes/model/programme'

interface ArchiveOptions {
  interactionHold?: Readonly<Ref<boolean>>
  restoration?: { ready(): Promise<void>; saved: Readonly<Ref<ArchiveBrowseState | null>> }
}

export function useProgrammeArchive(
  programmeId: Ref<string>,
  client: ProgrammeApi = usePlatform().programmes,
  cache?: ProgrammeCachePort,
  options: ArchiveOptions = {},
) {
  const dateSnapshots = useProgrammeSnapshot('dates', cache)
  const contentSnapshots = useProgrammeSnapshot('contents', cache)
  const dates = ref<ProgrammeDate[]>([])
  const selectedDate = ref<string | null>(null)
  const selectionNotice = ref('')
  const restoringDate = ref(false)
  const selectedDateId = computed(
    () => dates.value.find((item) => item.date === selectedDate.value)?.id ?? null,
  )
  const contents = computed(() => contentSnapshots.accepted.value?.items ?? [])
  let generation = 0
  let restored = false
  let disposed = false

  async function chooseDate() {
    const snapshot = dateSnapshots.accepted.value
    if (!snapshot) {
      return
    }

    const version = ++generation
    if (!restored && options.restoration) {
      restoringDate.value = true
      await options.restoration.ready()
      if (disposed || version !== generation) {
        return
      }
    }

    const saved = !restored ? options.restoration?.saved.value : null
    const wanted =
      selectedDate.value ?? (saved?.programmeId === programmeId.value ? saved.date : null)
    const selected = snapshot.items.find((date) => date.date === wanted)
    selectionNotice.value = wanted && !selected ? '原播出日期已不可用，已切换到最近日期。' : ''
    restored = true
    restoringDate.value = false
    // Updating dates also invalidates content when the same date now has a different ID.
    dates.value = snapshot.items
    selectedDate.value = selected?.date ?? snapshot.items[0]?.date ?? null
  }

  function loadDates() {
    const id = programmeId.value

    return dateSnapshots.load({ kind: 'dates', programmeId: id }, (signal) =>
      client.dates(id, signal),
    )
  }

  function loadContents() {
    const dateId = selectedDateId.value
    const id = programmeId.value
    if (!dateId) {
      contentSnapshots.reset()

      return Promise.resolve()
    }

    return contentSnapshots.load({ kind: 'contents', programmeId: id, dateId }, (signal) =>
      client.contents(id, dateId, signal),
    )
  }

  async function acceptUpdate() {
    if (options.interactionHold?.value) {
      return
    }

    dateSnapshots.acceptUpdate()
    // The selected-date watcher drops any content pending for a replaced date ID.
    await nextTick()
    contentSnapshots.acceptUpdate()
    await nextTick()
  }

  watch(
    dateSnapshots.accepted,
    () => {
      void chooseDate()
    },
    { flush: 'sync' },
  )
  watch(
    selectedDateId,
    () => {
      contentSnapshots.reset()
      void loadContents()
    },
    { flush: 'sync' },
  )
  watch(
    programmeId,
    () => {
      generation++
      restored = false
      dates.value = []
      selectedDate.value = null
      dateSnapshots.reset()
      contentSnapshots.reset()
      selectionNotice.value = ''
      void loadDates()
    },
    { immediate: true, flush: 'sync' },
  )

  onScopeDispose(() => {
    disposed = true
    generation++
  })

  return {
    dates,
    selectedDate,
    selectedDateId,
    contents,
    datesLoaded: computed(() => !!dateSnapshots.accepted.value && !restoringDate.value),
    contentsLoaded: computed(() => !!contentSnapshots.accepted.value),
    loadingDates: computed(() => dateSnapshots.loading.value || restoringDate.value),
    loadingContents: contentSnapshots.loading,
    dateError: dateSnapshots.error,
    contentError: contentSnapshots.error,
    loadDates,
    loadContents,
    acceptUpdate,
    selectionNotice,
    pendingUpdate: computed(
      () => dateSnapshots.pendingUpdate.value || contentSnapshots.pendingUpdate.value,
    ),
    cached: computed(() => dateSnapshots.cached.value || contentSnapshots.cached.value),
    fetchedAt: computed(() => contentSnapshots.fetchedAt.value ?? dateSnapshots.fetchedAt.value),
    refreshError: computed(
      () => contentSnapshots.refreshError.value || dateSnapshots.refreshError.value,
    ),
    cacheWarning: computed(
      () => contentSnapshots.cacheWarning.value || dateSnapshots.cacheWarning.value,
    ),
    refreshing: computed(() => dateSnapshots.refreshing.value || contentSnapshots.refreshing.value),
  }
}
