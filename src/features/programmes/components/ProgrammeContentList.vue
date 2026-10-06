<script setup lang="ts">
import { NButton, NCheckbox, NCheckboxGroup } from 'naive-ui'
import { Play } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'
import ProgrammeDownloadButton from './ProgrammeDownloadButton.vue'
import { getVideoVariants, resolveVideo } from '../video'

import type { ProgrammeContent, Quality } from '../types'

const selected = defineModel<string[]>({ required: true })
defineProps<{
  contents: ProgrammeContent[]
  fullIds: string[]
}>()
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
      :class="['content-row', { checked: selected.includes(content.id) }]"
    >
      <NCheckbox
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
        <span>
          <Play
            :size="15"
            fill="currentColor"
          />
        </span>
      </button>

      <div class="content-info">
        <div class="content-labels">
          <span class="content-index">{{ String(index + 1).padStart(2, '0') }}</span>
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
        <h3>{{ content.title }}</h3>
        <p>{{ videoAvailability(content) }}</p>
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
          @download="emit('download', [content], $event)"
        />
      </div>
    </article>
  </NCheckboxGroup>
</template>
