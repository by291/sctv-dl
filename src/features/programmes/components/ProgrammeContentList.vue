<script setup lang="ts">
import { computed, ref } from 'vue'
import { NButton, NCheckbox, NCheckboxGroup, NPopover, NTooltip } from 'naive-ui'
import { ArrowDownWideNarrow, ArrowUpNarrowWide, Play } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'
import ProgrammeDownloadButton from './ProgrammeDownloadButton.vue'
import { resolveVideo } from '../video'
import { programmeContentRows } from '../content'

import type { ProgrammeContent, Quality } from '../types'
import type { ContentSortOrder } from '../content'

const selected = defineModel<string[]>({ required: true })
const sortOrder = defineModel<ContentSortOrder>('sortOrder', { default: 'asc' })
const props = withDefaults(
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
const contentSortLabel = computed(() => (sortOrder.value === 'asc' ? '时间升序' : '时间降序'))
const rows = computed(() => programmeContentRows(props.contents, props.fullIds, sortOrder.value))
const groups = computed(() =>
  [
    { id: 'full', label: '整期节目', rows: rows.value.filter((row) => row.fullEpisode) },
    { id: 'clips', label: '节目片段', rows: rows.value.filter((row) => !row.fullEpisode) },
  ].filter((group) => group.rows.length),
)

function updateTitleVisibility(id: string, show: boolean) {
  visibleTitleId.value = show ? id : null
}

function closeTitle() {
  visibleTitleId.value = null
}

function toggleContentSort() {
  sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc'
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
    <section
      v-for="group in groups"
      :key="group.id"
      :aria-label="group.label"
      class="content-group"
      :class="{ 'full-episode-group': group.id === 'full' }"
    >
      <div
        v-if="group.id === 'clips'"
        class="group-toolbar"
      >
        <h3 class="group-heading">
          <span>{{ group.label }}</span>
          <span class="group-count">{{ group.rows.length }} 条</span>
        </h3>
        <NTooltip>
          <template #trigger>
            <NButton
              class="content-sort"
              :theme-overrides="{ heightMedium: '36px' }"
              quaternary
              circle
              :aria-label="`切换时间排序：当前${contentSortLabel}`"
              @click="toggleContentSort"
            >
              <template #icon>
                <component
                  :is="sortOrder === 'asc' ? ArrowUpNarrowWide : ArrowDownWideNarrow"
                  :size="19"
                />
              </template>
            </NButton>
          </template>
          {{ contentSortLabel }}，点击切换
        </NTooltip>
      </div>
      <div class="content-items">
        <article
          v-for="{ content, fullEpisode, publication } in group.rows"
          :key="content.id"
          class="content-row"
          :class="{ checked: selected.includes(content.id), 'full-episode-card': fullEpisode }"
        >
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
            <span
              v-if="hasVideo(content)"
              class="thumbnail-play"
            >
              <Play
                :size="fullEpisode ? 24 : 15"
                fill="currentColor"
              />
            </span>
          </button>

          <div class="content-info">
            <p
              v-if="fullEpisode"
              class="content-category"
            >
              整期节目
            </p>
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
            </h3>
            <p
              v-if="!fullEpisode"
              class="content-publication"
            >
              <time
                v-if="publication"
                :datetime="publication.datetime"
              >
                {{ publication.label }}
              </time>
              <span v-else>时间未知</span>
            </p>
            <div class="content-actions">
              <ProgrammeDownloadButton
                :contents="[content]"
                label="下载"
                compact
                :aria-label="`下载${content.title}`"
                :disabled="downloadingIds.length > 0"
                :loading="downloadingIds.includes(content.id)"
                @download="emit('download', [content], $event)"
              />
            </div>
          </div>
          <NCheckbox
            class="content-checkbox"
            :value="content.id"
            :disabled="!hasVideo(content)"
            :aria-label="`选择${content.title}`"
          />
        </article>
      </div>
    </section>
  </NCheckboxGroup>
</template>

<style scoped>
.content-list {
  display: grid;
  gap: 16px;
  animation: content-reveal var(--motion-normal) var(--motion-ease);
}
.content-group {
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--panel);
}
.full-episode-group {
  overflow: visible;
  border: 0;
  border-radius: 0;
  background: transparent;
}
.content-items {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
}
.full-episode-group .content-items {
  gap: 16px;
}
.group-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  min-height: 64px;
  border-bottom: 1px solid var(--line);
  padding: 12px 24px;
}
.content-sort {
  margin-right: -8px;
}
.content-sort:focus:not(:focus-visible):not(:hover):not(:active) {
  background-color: transparent;
}
.group-heading {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 16px;
  line-height: 1.5;
  font-weight: 600;
}
.group-count {
  border-radius: 6px;
  background: var(--subtle);
  padding: 2px 7px;
  color: var(--muted);
  font-size: 13px;
  line-height: 1.5;
  font-weight: 400;
}
.content-row {
  display: grid;
  grid-template-columns: 208px minmax(0, 1fr) 20px;
  grid-template-areas: 'thumbnail info selection';
  align-items: start;
  gap: 24px;
  border-bottom: 1px solid var(--line);
  padding: 20px 24px;
  transition:
    color 140ms ease,
    background-color 140ms ease,
    border-color 140ms ease;
}
.content-row:last-child {
  border-bottom: 0;
}
.content-row.checked {
  background: color-mix(in srgb, var(--accent-soft) 45%, var(--panel));
}
.content-row.full-episode-card {
  grid-template-columns: 288px minmax(0, 1fr) 20px;
  align-items: center;
  gap: 24px;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--panel);
  padding: 24px;
}
.full-episode-card.checked {
  background: color-mix(in srgb, var(--accent-soft) 45%, var(--panel));
}
.full-episode-card .content-thumbnail {
  width: 100%;
  border-radius: 8px;
}
.full-episode-card .content-info {
  align-self: center;
}
.content-category {
  margin-bottom: 10px;
  color: var(--accent);
  font-size: 13px;
  line-height: 1.5;
  font-weight: 500;
}
.full-episode-card .content-title {
  font-size: 22px;
  line-height: 1.5;
  font-weight: 600;
}
.full-episode-card .content-actions {
  margin-top: 20px;
  padding-top: 0;
}
.content-checkbox {
  grid-area: selection;
  min-height: 44px;
  align-self: center;
  align-items: center;
  color: var(--muted);
}
.content-thumbnail {
  grid-area: thumbnail;
  align-self: start;
  position: relative;
  aspect-ratio: 16 / 9;
  width: 208px;
  overflow: hidden;
  border-radius: 7px;
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
  grid-area: info;
  display: flex;
  flex-direction: column;
  align-self: stretch;
  min-width: 0;
}
.content-heading {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 400;
}
.content-publication {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 6px;
  margin-top: 4px;
  font-size: 13px;
  line-height: 1.5;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}
.content-publication time {
  white-space: nowrap;
}
.content-unavailable {
  margin-bottom: 7px;
  color: var(--muted);
}
.content-title {
  display: -webkit-box;
  min-width: 0;
  max-width: min(100%, 88ch);
  overflow: hidden;
  border: 0;
  padding: 0;
  background: transparent;
  color: var(--text);
  font-size: 16px;
  line-height: 1.5;
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
.content-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  margin-top: auto;
  padding-top: 8px;
}
@media (width < 1020px) {
  .content-row.full-episode-card {
    grid-template-columns: 220px minmax(0, 1fr) 20px;
    gap: 20px;
  }
  .full-episode-card .content-title {
    font-size: 20px;
  }
}
@media (width < 760px) {
  .group-toolbar {
    min-height: 60px;
    padding: 8px 16px;
  }
  .content-sort {
    min-width: 44px;
    min-height: 44px;
    margin-right: -12px;
  }
  .content-row {
    grid-template-columns: 88px minmax(0, 1fr) 20px;
    align-items: start;
    gap: 12px;
    padding: 16px;
  }
  .content-checkbox {
    min-height: 44px;
    align-items: center;
  }
  .content-thumbnail {
    grid-area: thumbnail;
    width: 88px;
  }
  .content-info {
    grid-area: info;
    align-self: start;
  }
  .content-unavailable {
    margin-bottom: 4px;
  }
  .content-title {
    padding: 0;
    font-size: 15px;
    line-height: 1.5;
  }
  .content-publication {
    font-size: 12px;
  }
  .content-publication time {
    white-space: normal;
  }
  .content-row.full-episode-card {
    grid-template-columns: minmax(0, 1fr) 20px;
    grid-template-areas:
      'thumbnail selection'
      'info selection';
    gap: 16px;
    padding: 16px;
  }
  .full-episode-card .content-title {
    font-size: 18px;
  }
  .content-actions {
    padding-top: 12px;
  }
  .full-episode-card .content-actions {
    margin-top: 16px;
  }
}
</style>
