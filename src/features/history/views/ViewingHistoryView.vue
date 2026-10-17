<script setup lang="ts">
import { computed, nextTick, ref, useTemplateRef } from 'vue'
import { NButton, NInput, NPopconfirm } from 'naive-ui'

import { historyKey } from '@shared/contracts/history'
import { useHistoryStore } from '@/features/history/stores/useHistoryStore'
import { useHistoryPreview } from '@/features/history/composables/useHistoryPreview'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import ViewingHistoryCard from '@/features/history/components/ViewingHistoryCard.vue'
import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import StatePanel from '@/shared/components/StatePanel.vue'
import { usePageScroll } from '@/shared/navigation/page-scroll'

import type { HistoryEntry } from '@shared/contracts/history'

const { pageScrollPosition, scrollPageTo } = usePageScroll()

const history = useHistoryStore()
const settings = useSettingsStore()
const { content, input, open } = useHistoryPreview()
const query = ref('')
const results = useTemplateRef<HTMLElement>('results')
const heading = useTemplateRef<HTMLElement>('heading')
const filtered = computed(() => {
  const search = query.value.trim().toLocaleLowerCase()

  return history.entries.filter((entry) =>
    `${entry.title} ${entry.programmeName} ${entry.broadcastDate}`
      .toLocaleLowerCase()
      .includes(search),
  )
})
const days = computed(() => {
  const groups = new Map<string, HistoryEntry[]>()
  for (const entry of filtered.value) {
    const day = new Date(entry.viewedAt).toLocaleDateString('zh-CN')
    const entries = groups.get(day) ?? []
    entries.push(entry)
    groups.set(day, entries)
  }

  return [...groups].map(([date, entries]) => ({ date, entries }))
})

async function remove(entry: HistoryEntry): Promise<void> {
  const index = filtered.value.findIndex(
    (value) => historyKey(value.content) === historyKey(entry.content),
  )
  const active = document.activeElement
  const restoreFocus = active instanceof HTMLElement && !!results.value?.contains(active)
  const scroll = pageScrollPosition()
  await history.remove(entry.content)
  await nextTick()
  if (!history.error && restoreFocus) {
    const cards = results.value?.querySelectorAll<HTMLElement>('.history-card')
    const card = cards?.[Math.min(index, cards.length - 1)]
    ;(card?.querySelector<HTMLElement>('button') ?? heading.value)?.focus({ preventScroll: true })
  }

  scrollPageTo(scroll)
}
</script>

<template>
  <div class="history-view">
    <section class="page-heading">
      <h1
        ref="heading"
        tabindex="-1"
      >
        观看历史
      </h1>
      <NPopconfirm @positive-click="history.clear">
        <template #trigger>
          <NButton
            :disabled="!history.entries.length"
            secondary
          >
            清空历史
          </NButton>
        </template>
        清空全部观看历史？此操作不会删除下载文件。
      </NPopconfirm>
    </section>
    <NInput
      v-model:value="query"
      class="history-search"
      placeholder="搜索节目、栏目或日期"
      aria-label="搜索观看历史"
      clearable
    />
    <p
      v-if="history.warning"
      class="history-warning"
      role="status"
    >
      {{ history.warning }}
    </p>
    <StatePanel
      v-if="history.loading && !history.entries.length"
      loading
    />
    <StatePanel
      v-else-if="history.error"
      title="观看历史暂不可用"
      :error="history.error"
      @retry="history.reload"
    />
    <StatePanel
      v-if="!history.loading && !history.error && !filtered.length"
      :title="query ? '没有找到匹配的记录' : '还没有观看记录'"
      description="播放节目后，可在这里继续观看。"
    />
    <div
      ref="results"
      class="history-results"
    >
      <section
        v-for="day in days"
        :key="day.date"
        class="history-day"
      >
        <h2>{{ day.date }}</h2>
        <ViewingHistoryCard
          v-for="entry in day.entries"
          :key="historyKey(entry.content)"
          :entry="entry"
          @play="open"
          @remove="remove"
        />
      </section>
    </div>
    <ProgrammePreviewDialog
      v-if="input"
      v-model="content"
      :input="input"
      :reference="input.metadata.content"
      :quality="settings.quality"
    />
  </div>
</template>

<style scoped>
.history-search {
  max-width: 480px;
  margin-bottom: 20px;
}
.history-results,
.history-day {
  display: grid;
  gap: 12px;
}
.history-results {
  gap: 24px;
}
.history-day h2 {
  font-size: 14px;
  font-weight: 500;
  color: var(--muted);
}
.history-warning {
  margin-bottom: 16px;
  color: var(--muted);
  font-size: 14px;
}
</style>
