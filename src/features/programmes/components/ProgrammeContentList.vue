<script setup lang="ts">
import { NButton, NCheckbox, NCheckboxGroup } from 'naive-ui'
import { Play } from '@lucide/vue'

import CoverImage from '../../../components/CoverImage.vue'
import { resolveVideo } from '../video'

import type { ProgrammeContent, Quality } from '../types'

const selected = defineModel<string[]>({ required: true })
const props = defineProps<{
  contents: ProgrammeContent[]
  fullIds: string[]
  quality: Quality
  videoNote: (content: ProgrammeContent) => string
}>()
const emit = defineEmits<{ preview: [content: ProgrammeContent] }>()

function hasVideo(content: ProgrammeContent): boolean {
  return !!resolveVideo(content, props.quality)
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
        <p>{{ videoNote(content) }}</p>
      </div>

      <NButton
        quaternary
        circle
        :disabled="!hasVideo(content)"
        :aria-label="`预览${content.title}`"
        @click="emit('preview', content)"
      >
        <Play :size="17" />
      </NButton>
    </article>
  </NCheckboxGroup>
</template>
