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
const progressPercent = computed(() => {
  if (props.entry.completed) {
    return 100
  }

  if (!props.entry.durationMs) {
    return 0
  }

  return Math.min(100, Math.max(0, (props.entry.positionMs / props.entry.durationMs) * 100))
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
      <span
        class="history-progress"
        :class="{ completed: entry.completed }"
        :style="{ width: `${progressPercent}%` }"
        aria-hidden="true"
      />
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
  border-radius: var(--radius);
  padding: 14px;
  background: var(--panel);
}
.history-cover {
  position: relative;
  border: 0;
  padding: 0;
  width: 148px;
  flex-shrink: 0;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: 4px;
  background: var(--subtle);
}
.history-cover-play {
  position: absolute;
  bottom: 8px;
  left: 8px;
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border-radius: 50%;
  border: 1px solid #ffffff33;
  background: color-mix(in srgb, var(--rail) 78%, transparent);
  backdrop-filter: blur(6px);
  color: #fff;
  transition:
    background-color var(--motion-fast) var(--motion-ease),
    transform var(--motion-fast) var(--motion-ease);
}
.history-progress {
  position: absolute;
  bottom: 0;
  left: 0;
  height: 3px;
  background: var(--accent);
}
.history-progress.completed {
  background: var(--green);
}
.history-cover:hover .history-cover-play {
  background: var(--accent-fill);
  transform: scale(1.05);
}
.history-copy {
  flex: 1;
  min-width: 0;
}
.history-copy h3 {
  font-size: 16px;
  line-height: 1.4;
  font-weight: 600;
  overflow-wrap: anywhere;
}
.history-copy p,
.history-copy > span {
  font-size: 12px;
  color: var(--muted);
  line-height: 1.7;
  font-variant-numeric: tabular-nums;
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
    width: 104px;
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
