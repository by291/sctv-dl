<script setup lang="ts">
import { computed } from 'vue'
import { NButton, NSelect } from 'naive-ui'
import { CalendarDays, RefreshCw } from '@lucide/vue'

import type { ProgrammeDate } from '@/features/programmes/model/programme'

const selectedDate = defineModel<string | null>({ required: true })
const props = defineProps<{ dates: ProgrammeDate[]; loading: boolean }>()
const emit = defineEmits<{ refresh: [] }>()

const refreshButtonTheme = { heightMedium: '42px' }

const options = computed(() => props.dates.map((item) => ({ label: item.date, value: item.date })))
const recentDates = computed(() =>
  props.dates.slice(0, 7).map((item) => {
    const date = new Date(`${item.date}T00:00:00`)

    return {
      value: item.date,
      day: String(date.getDate()).padStart(2, '0'),
      month: `${date.getMonth() + 1}月`,
      weekday: date.toLocaleDateString('zh-CN', { weekday: 'short' }),
    }
  }),
)
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
        :theme-overrides="refreshButtonTheme"
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
    role="group"
    aria-label="最近播出日期"
  >
    <span class="recent-label">最近播出</span>
    <button
      v-for="date in recentDates"
      :key="date.value"
      class="date-button"
      :class="{ active: date.value === selectedDate }"
      :aria-pressed="date.value === selectedDate"
      @click="selectedDate = date.value"
    >
      <span class="date-day">{{ date.day }}</span>
      <span class="date-meta">{{ date.month }} {{ date.weekday }}</span>
    </button>
  </div>
</template>

<style scoped>
.date-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
  padding: 18px 22px 12px;
}
.date-heading {
  font-size: 16px;
  font-weight: 600;
}
.date-control {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--muted);
}
.date-select {
  width: 215px;
}
.recent-dates {
  display: flex;
  flex-wrap: wrap;
  align-items: stretch;
  gap: 6px;
  padding: 0 22px 18px;
}
.recent-label {
  align-self: center;
  margin-right: 8px;
  font-size: 12px;
  color: var(--muted);
}
.date-button {
  display: flex;
  min-width: 60px;
  flex-direction: column;
  align-items: center;
  gap: 1px;
  border-radius: 5px;
  border: 1px solid transparent;
  background: transparent;
  padding: 7px 9px;
  color: var(--muted);
  transition:
    color var(--motion-fast) var(--motion-ease),
    background-color var(--motion-fast) var(--motion-ease),
    border-color var(--motion-fast) var(--motion-ease);
}
.date-day {
  font-size: 17px;
  line-height: 1.2;
  font-weight: 700;
  color: var(--text);
  font-variant-numeric: tabular-nums;
}
.date-meta {
  font-size: 11px;
  line-height: 1.3;
  white-space: nowrap;
}
.date-button.active {
  border-color: var(--rail);
  background: var(--rail);
  color: var(--hero-muted);
}
.date-button.active .date-day {
  color: var(--hero-text);
}
@media (hover: hover) {
  .date-button:hover {
    background: var(--subtle);
    color: var(--text);
  }
  .date-button.active:hover {
    border-color: var(--rail);
    background: var(--rail);
    color: var(--hero-muted);
  }
}
@media (width < 760px) {
  .date-toolbar {
    padding: 16px 16px 12px;
  }
  .date-heading,
  .recent-label {
    display: none;
  }
  .date-control {
    width: 100%;
  }
  .date-select {
    min-width: 0;
    width: auto;
    flex: 1;
  }
  .recent-dates {
    flex-wrap: nowrap;
    overflow-x: auto;
    gap: 4px;
    margin-top: -4px;
    padding: 6px 16px 14px;
    scrollbar-width: thin;
  }
  .date-button {
    min-width: 56px;
    min-height: 48px;
    flex-shrink: 0;
    padding: 6px 8px;
  }
}
</style>
