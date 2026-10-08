<script setup lang="ts">
import { NButton, NCheckbox, NCheckboxGroup } from 'naive-ui'
import { Play } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'
import ProgrammeDownloadButton from './ProgrammeDownloadButton.vue'
import { getVideoVariants, resolveVideo } from '../video'

import type { ProgrammeContent, Quality } from '../types'

const selected = defineModel<string[]>({ required: true })
withDefaults(
  defineProps<{
    contents: ProgrammeContent[]
    fullIds: string[]
    downloadingIds?: string[]
  }>(),
  { downloadingIds: () => [] },
)
const emit = defineEmits<{
  preview: [content: ProgrammeContent]
  download: [contents: ProgrammeContent[], quality: Quality]
}>()

function hasVideo(content: ProgrammeContent): boolean {
  return !!resolveVideo(content, 'standard')
}

function videoAvailability(content: ProgrammeContent): string {
  const variants = getVideoVariants(content)

  return variants.length
    ? variants.map(({ quality }) => (quality === 'standard' ? '标准' : '流畅')).join(' / ') + '画质'
    : '暂无可用视频'
}
</script>

<template>
  <NCheckboxGroup
    v-model:value="selected"
    class="content-list"
  >
    <article
      v-for="(content, index) in contents"
      :key="content.id"
      class="content-row"
      :class="{ checked: selected.includes(content.id) }"
    >
      <NCheckbox
        class="content-checkbox"
        :value="content.id"
        :disabled="!hasVideo(content)"
        :aria-label="`选择${content.title}`"
      />
      <button
        class="content-thumbnail"
        :disabled="!hasVideo(content)"
        :aria-label="`预览${content.title}`"
        @click="emit('preview', content)"
      >
        <CoverImage
          :src="content.cover"
          :alt="content.title"
        />
        <span class="thumbnail-play">
          <Play
            :size="15"
            fill="currentColor"
          />
        </span>
      </button>

      <div class="content-info">
        <div class="content-labels">
          <span class="content-index">
            {{ String(index + 1).padStart(2, '0') }}
          </span>
          <span
            v-if="fullIds.includes(content.id)"
            class="pill coral"
          >
            整期节目
          </span>
          <span
            v-else
            class="pill"
          >
            节目片段
          </span>
          <span
            v-if="!hasVideo(content)"
            class="muted"
          >
            暂无视频
          </span>
        </div>
        <h3 class="content-title">
          {{ content.title }}
        </h3>
        <p class="content-availability">{{ videoAvailability(content) }}</p>
      </div>

      <div class="content-row-actions">
        <NButton
          class="preview-button"
          quaternary
          circle
          :disabled="!hasVideo(content)"
          :aria-label="`预览${content.title}`"
          @click="emit('preview', content)"
        >
          <template #icon><Play :size="17" /></template>
        </NButton>
        <ProgrammeDownloadButton
          :contents="[content]"
          label="下载"
          :aria-label="`下载${content.title}`"
          :disabled="downloadingIds.length > 0"
          :loading="downloadingIds.includes(content.id)"
          @download="emit('download', [content], $event)"
        />
      </div>
    </article>
  </NCheckboxGroup>
</template>

<style scoped>
.content-list {
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
.content-row {
  display: flex;
  align-items: center;
  gap: 18px;
  border-bottom: 1px solid var(--line);
  padding: 18px 24px;
  transition:
    color 140ms ease,
    background-color 140ms ease,
    border-color 140ms ease;
}
.content-row:last-child {
  border-bottom-left-radius: 11px;
  border-bottom-right-radius: 11px;
  border-bottom: 0;
}
.content-row.checked {
  background: color-mix(in srgb, var(--accent-soft) 45%, var(--panel));
}
.content-thumbnail {
  position: relative;
  aspect-ratio: 16 / 9;
  width: 126px;
  flex-shrink: 0;
  overflow: hidden;
  border-radius: 6px;
  border: 0;
  padding: 0;
}
.thumbnail-play {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  background: #00000020;
  color: white;
}
.content-info {
  min-width: 0;
  flex: 1;
}
.content-labels {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-bottom: 7px;
}
.content-index {
  font-size: 14px;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}
.muted {
  color: var(--muted);
}
.content-title {
  font-size: 16px;
  line-height: 1.7;
  font-weight: 500;
  overflow-wrap: anywhere;
}
.content-availability {
  margin-top: 6px;
  font-size: 14px;
  color: var(--muted);
}
.content-row-actions {
  display: flex;
  flex-shrink: 0;
  align-items: center;
  gap: 8px;
}
.preview-button {
  width: 42px !important;
  height: 42px !important;
}
@media (width < 760px) {
  .content-row {
    display: grid;
    grid-template-columns: 20px 88px minmax(0, 1fr);
    gap: 12px;
    padding-inline: 20px;
  }
  .content-checkbox {
    grid-row: span 2;
  }
  .content-thumbnail {
    grid-row: span 2;
    width: 88px;
  }
  .content-labels {
    margin-bottom: 4px;
  }
  .content-row-actions {
    grid-column-start: 3;
    justify-self: end;
  }
  .preview-button {
    display: none !important;
  }
}
@media (width < 440px) {
  .content-row {
    grid-template-columns: 20px 72px minmax(0, 1fr);
    gap: 10px;
    padding-inline: 14px;
  }
  .content-thumbnail {
    width: 72px;
  }
}
</style>
