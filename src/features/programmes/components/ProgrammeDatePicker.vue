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
      <h2 class="date-heading">选择播出日期</h2>
    </div>

    <div class="date-control">
      <CalendarDays :size="18" />
      <NSelect
        v-model:value="selectedDate"
        class="date-select"
        :options="options"
        filterable
        :disabled="loading || !dates.length"
        :aria-busy="loading"
        placeholder="搜索或选择播出日期"
        aria-label="播出日期"
      />
      <NButton
        class="date-refresh"
        quaternary
        circle
        aria-label="重新读取播出日期"
        :loading="loading"
        @click="emit('refresh')"
      >
        <template #icon><RefreshCw :size="16" /></template>
      </NButton>
    </div>
  </div>

  <div
    v-if="dates.length"
    class="recent-dates"
  >
    <span class="recent-label">最近播出</span>
    <button
      v-for="date in dates.slice(0, 7)"
      :key="date.id"
      class="date-button"
      :class="{ active: date.date === selectedDate }"
      :aria-pressed="date.date === selectedDate"
      @click="selectedDate = date.date"
    >
      {{ date.date.slice(5).replace('-', '月') }}日
    </button>
  </div>
</template>

<style scoped>
.date-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  padding: 24px;
}
.date-heading {
  font-size: 18px;
  font-weight: 600;
}
.date-control {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--muted);
}
.date-select {
  width: 215px !important;
}
.date-refresh {
  width: 42px !important;
  height: 42px !important;
}
.recent-dates {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  border-bottom: 1px solid var(--line);
  padding: 0 24px 23px;
}
.recent-label {
  margin-right: 10px;
  font-size: 14px;
  color: var(--muted);
}
.date-button {
  border-radius: 6px;
  border: 1px solid transparent;
  background: var(--subtle);
  padding: 7px 10px;
  font-size: 14px;
  color: var(--muted);
  transition:
    color 140ms ease,
    background-color 140ms ease,
    border-color 140ms ease;
}
.date-button.active {
  border-color: #dc4f4135;
  background: var(--accent-soft);
  color: var(--accent);
}
@media (hover: hover) {
  .date-button:hover {
    background: var(--accent-soft);
    color: var(--accent);
  }
}
@media (width < 760px) {
  .date-toolbar {
    flex-direction: column;
    align-items: flex-start;
    gap: 15px;
    padding: 20px;
  }
  .date-control {
    width: 100%;
  }
  .date-select {
    width: auto !important;
    flex: 1;
  }
  .recent-dates {
    gap: 7px;
    padding-inline: 20px;
    padding-bottom: 20px;
  }
  .recent-label {
    margin-bottom: 3px;
    width: 100%;
  }
}
</style>
