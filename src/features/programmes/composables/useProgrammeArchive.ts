import { onScopeDispose, ref, watch } from 'vue'

import { programmeApi } from '@/features/programmes/api/programme-api'
import { errorMessage } from '@/shared/utils/errors'
import { LatestRequest } from '@/shared/utils/latest-request'

import type { Ref } from 'vue'
import type { ProgrammeApi } from '@/features/programmes/api/programme-api'
import type { ProgrammeContent, ProgrammeDate } from '@/features/programmes/model/programme'

export function useProgrammeArchive(programmeId: Ref<string>, client: ProgrammeApi = programmeApi) {
  const dates = ref<ProgrammeDate[]>([])
  const selectedDate = ref<string | null>(null)
  const contents = ref<ProgrammeContent[]>([])
  const loadingDates = ref(false)
  const loadingContents = ref(false)
  const dateError = ref('')
  const contentError = ref('')

  const dateGate = new LatestRequest()
  const contentGate = new LatestRequest()

  async function loadDates() {
    const request = dateGate.begin()
    contentGate.cancel()
    dates.value = []
    contents.value = []
    selectedDate.value = null
    dateError.value = ''
    contentError.value = ''
    loadingContents.value = false
    loadingDates.value = true

    try {
      const data = await client.dates(programmeId.value, request.signal)

      if (request.isCurrent()) {
        dates.value = data
        selectedDate.value = data[0]?.date ?? null
      }
    } catch (cause) {
      if (request.isCurrent()) {
        dateError.value = errorMessage(cause)
      }
    } finally {
      if (request.isCurrent()) {
        loadingDates.value = false
      }
    }
  }

  async function loadContents() {
    const request = contentGate.begin()
    contents.value = []
    contentError.value = ''
    const date = dates.value.find((item) => item.date === selectedDate.value)

    if (!date) {
      loadingContents.value = false

      return
    }

    loadingContents.value = true

    try {
      const data = await client.contents(programmeId.value, date.id, request.signal)

      if (request.isCurrent()) {
        contents.value = data
      }
    } catch (cause) {
      if (request.isCurrent()) {
        contentError.value = errorMessage(cause)
      }
    } finally {
      if (request.isCurrent()) {
        loadingContents.value = false
      }
    }
  }

  watch(
    programmeId,
    () => {
      void loadDates()
    },
    { immediate: true },
  )
  watch(selectedDate, () => {
    void loadContents()
  })

  onScopeDispose(() => {
    dateGate.cancel()
    contentGate.cancel()
  })

  return {
    dates,
    selectedDate,
    contents,
    loadingDates,
    loadingContents,
    dateError,
    contentError,
    loadDates,
    loadContents,
  }
}
