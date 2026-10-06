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
      <h2 class="text-[18px] font-semibold">选择播出日期</h2>
    </div>

    <div class="date-control flex items-center gap-[10px] text-muted max-[760px]:w-full">
      <CalendarDays :size="18" />
      <NSelect
        v-model:value="selectedDate"
        class="w-[215px]! max-[760px]:w-auto! max-[760px]:flex-1"
        :options="options"
        filterable
        :disabled="loading || !dates.length"
        :aria-busy="loading"
        placeholder="搜索或选择播出日期"
        aria-label="播出日期"
      />
      <NButton
        class="size-[42px]!"
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
    <span class="mr-[10px] text-meta text-muted max-[760px]:mb-[3px] max-[760px]:w-full">
      最近播出
    </span>
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
@reference '../../../styles/global.css';

@layer components {
  .date-button {
    @apply rounded-[6px] border border-transparent bg-subtle px-[10px] py-[7px] text-meta text-muted;
    @apply transition-colors duration-[140ms] ease-[ease] hover:bg-accent-soft hover:text-accent;
  }

  .date-button.active {
    @apply border-[#dc4f4135] bg-accent-soft text-accent;
  }

  .date-toolbar {
    @apply flex items-center justify-between gap-5 p-6;

    @variant max-[760px] {
      @apply flex-col items-start gap-[15px] p-5;
    }
  }

  .recent-dates {
    @apply flex flex-wrap items-center gap-2 border-b border-line px-6 pb-[23px];

    @variant max-[760px] {
      @apply gap-[7px] px-5 pb-5;
    }
  }
}
</style>
