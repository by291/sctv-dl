<script setup lang="ts">
import { computed } from 'vue'
import { NButton, NSelect } from 'naive-ui'
import { CalendarDays, RefreshCw } from '@lucide/vue'

import type { ProgrammeDate } from '../types'

const selectedDate = defineModel<string | null>({ required: true })
const props = defineProps<{ dates: ProgrammeDate[]; loading: boolean }>()
const emit = defineEmits<{ refresh: [] }>()

const options = computed(() => props.dates.map((item) => ({ label: item.date, value: item.date })))
</script>

<template>
  <div class="date-toolbar">
    <div>
      <h2>选择播出日期</h2>
      <p>可搜索年月日，查看历史节目。</p>
    </div>

    <div class="date-control">
      <CalendarDays :size="18" />
      <NSelect
        v-model:value="selectedDate"
        :options="options"
        filterable
        :disabled="loading || !dates.length"
        :loading="loading"
        placeholder="搜索或选择播出日期"
        aria-label="播出日期"
      />
      <NButton
        quaternary
        circle
        aria-label="重新读取播出日期"
        :loading="loading"
        @click="emit('refresh')"
      >
        <RefreshCw :size="16" />
      </NButton>
    </div>
  </div>

  <div
    v-if="dates.length"
    class="recent-dates"
  >
    <span>最近播出</span>
    <button
      v-for="date in dates.slice(0, 7)"
      :key="date.id"
      :class="{ active: date.date === selectedDate }"
      :aria-pressed="date.date === selectedDate"
      @click="selectedDate = date.date"
    >
      {{ date.date.slice(5).replace('-', '月') }}日
    </button>
  </div>
</template>
