<script setup lang="ts">
import { ref } from 'vue'
import { NButton, NCheckbox, NCheckboxGroup, NPopover } from 'naive-ui'
import { Play } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'
import ProgrammeDownloadButton from './ProgrammeDownloadButton.vue'
import { resolveVideo } from '../video'

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

const visibleTitleId = ref<string | null>(null)

function updateTitleVisibility(id: string, show: boolean) {
  visibleTitleId.value = show ? id : null
}

function closeTitle() {
  visibleTitleId.value = null
}

function hasVideo(content: ProgrammeContent): boolean {
  return !!resolveVideo(content, 'standard')
}
</script>

<template>
  <NCheckboxGroup
    v-model:value="selected"
    class="content-list"
  >
    <article
      v-for="content in contents"
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
        <p
          v-if="!hasVideo(content)"
          class="content-unavailable"
        >
          暂无视频
        </p>
        <h3 class="content-heading">
          <NPopover
            class="content-title-popover"
            trigger="click"
            placement="top-start"
            :show="visibleTitleId === content.id"
            @update:show="updateTitleVisibility(content.id, $event)"
          >
            <template #trigger>
              <button
                type="button"
                class="content-title"
                :title="content.title"
                :aria-label="`查看完整标题：${content.title}`"
                :aria-expanded="visibleTitleId === content.id"
                @keydown.esc="closeTitle"
                @blur="closeTitle"
              >
                {{ content.title }}
              </button>
            </template>
            {{ content.title }}
          </NPopover>
          <span
            v-if="fullIds.includes(content.id)"
            class="pill coral content-full"
          >
            整期节目
          </span>
        </h3>
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
.content-heading {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 400;
}
.content-full {
  flex-shrink: 0;
}
.content-unavailable {
  margin-bottom: 7px;
  color: var(--muted);
}
.content-title {
  display: -webkit-box;
  min-width: 0;
  max-width: 100%;
  overflow: hidden;
  border: 0;
  background: transparent;
  color: var(--text);
  font-size: 16px;
  line-height: 1.7;
  font-weight: 500;
  text-align: left;
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}
/* The library teleports the full title outside the scoped content list. */
:global(.content-title-popover) {
  max-width: min(480px, calc(100vw - 32px));
  overflow-wrap: anywhere;
}
:global(.content-title-popover .n-popover__content) {
  max-height: min(320px, calc(50dvh - 48px));
  overflow-y: auto;
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
    grid-template-columns: 24px 88px minmax(0, 1fr);
    grid-template-areas:
      'check info info'
      '. thumbnail actions';
    align-items: start;
    gap: 12px;
    padding: 16px;
  }
  .content-checkbox {
    grid-area: check;
    min-height: 44px;
    align-items: center;
  }
  .content-thumbnail {
    grid-area: thumbnail;
    width: 88px;
  }
  .content-info {
    grid-area: info;
  }
  .content-unavailable {
    margin-bottom: 4px;
  }
  .content-title {
    min-height: 44px;
    line-height: 1.5;
  }
  .content-row-actions {
    grid-area: actions;
    align-self: center;
    justify-self: end;
  }
  .preview-button {
    display: none !important;
  }
}
</style>
