<script setup lang="ts">
import { computed } from 'vue'
import { NButton } from 'naive-ui'
import { Play, Trash2 } from '@lucide/vue'

import CoverImage from '@/shared/components/CoverImage.vue'

import type { HistoryEntry } from '@shared/contracts/history'

const props = defineProps<{ entry: HistoryEntry }>()
defineEmits<{ play: [entry: HistoryEntry]; remove: [entry: HistoryEntry] }>()
const progress = computed(() => {
  if (props.entry.completed) {
    return '已看完'
  }

  const seconds = Math.floor(props.entry.positionMs / 1000)

  return `看到 ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
})
</script>

<template>
  <article class="history-card">
    <button
      type="button"
      class="history-cover"
      :aria-label="`播放封面：${entry.title}`"
      @click="$emit('play', entry)"
    >
      <CoverImage
        :src="entry.cover"
        :alt="entry.title"
      />
      <span
        class="history-cover-play"
        aria-hidden="true"
      >
        <Play
          :size="24"
          fill="currentColor"
        />
      </span>
    </button>
    <div class="history-copy">
      <h3>{{ entry.title }}</h3>
      <p>{{ entry.programmeName }} · {{ entry.broadcastDate }}</p>
      <span>{{ progress }}</span>
    </div>
    <div class="history-actions">
      <NButton
        secondary
        :aria-label="`${entry.completed ? '重新播放' : '继续观看'}：${entry.title}`"
        @click="$emit('play', entry)"
      >
        <template #icon><Play :size="16" /></template>
        {{ entry.completed ? '重新播放' : '继续观看' }}
      </NButton>
      <NButton
        quaternary
        :aria-label="`删除记录：${entry.title}`"
        @click="$emit('remove', entry)"
      >
        <template #icon><Trash2 :size="16" /></template>
      </NButton>
    </div>
  </article>
</template>

<style scoped>
.history-card {
  display: flex;
  align-items: center;
  gap: 16px;
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 16px;
  background: var(--panel);
}
.history-cover {
  position: relative;
  border: 0;
  padding: 0;
  width: 144px;
  flex-shrink: 0;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: 8px;
}
.history-cover-play {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  background: #00000020;
  color: white;
}
.history-cover:hover .history-cover-play {
  background: #00000040;
}
.history-copy {
  flex: 1;
  min-width: 0;
}
.history-copy h3 {
  font-size: 16px;
  overflow-wrap: anywhere;
}
.history-copy p,
.history-copy span {
  font-size: 13px;
  color: var(--muted);
  line-height: 1.8;
}
.history-actions {
  display: flex;
  gap: 4px;
  align-items: center;
}
@media (width < 760px) {
  .history-card {
    flex-wrap: wrap;
    gap: 12px;
    padding: 12px;
  }
  .history-cover {
    position: relative;
    border: 0;
    padding: 0;
    width: 100px;
  }
  .history-actions {
    width: 100%;
    justify-content: flex-end;
  }
  .history-actions :deep(.n-button) {
    min-height: 44px;
  }
}
</style>
