import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api } from './api'
import { errorMessage } from '../../shared/errors'
import { LatestRequest } from '../../shared/latest-request'

import type { Programme } from './types'

export const useProgrammeStore = defineStore('programmes', () => {
  const programmes = ref<Programme[]>([])
  const loading = ref(false)
  const error = ref('')
  const updatedAt = ref<Date | null>(null)
  const gate = new LatestRequest()

  async function load(force = false) {
    if (!force && (programmes.value.length || loading.value)) {
      return
    }

    const request = gate.begin()
    loading.value = true
    error.value = ''

    try {
      const data = await api.programmes(request.signal)

      if (request.isCurrent()) {
        programmes.value = data
        updatedAt.value = new Date()
      }
    } catch (cause) {
      if (request.isCurrent()) {
        error.value = errorMessage(cause)
      }
    } finally {
      if (request.isCurrent()) {
        loading.value = false
      }
    }
  }

  return { programmes, loading, error, updatedAt, load }
})
