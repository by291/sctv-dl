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
    class="content-list animate-content-reveal"
  >
    <article
      v-for="(content, index) in contents"
      :key="content.id"
      class="content-row"
      :class="{ checked: selected.includes(content.id) }"
    >
      <NCheckbox
        class="max-[760px]:row-span-2"
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
        <span class="absolute inset-0 grid place-items-center bg-[#00000020] text-white">
          <Play
            :size="15"
            fill="currentColor"
          />
        </span>
      </button>

      <div class="content-info min-w-0 flex-1">
        <div class="content-labels mb-[7px] flex items-center gap-[9px] max-[760px]:mb-1">
          <span class="content-index text-meta text-muted tabular-nums">
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
            class="muted text-muted"
          >
            暂无视频
          </span>
        </div>
        <h3 class="text-body leading-[1.7] font-medium [overflow-wrap:anywhere]">
          {{ content.title }}
        </h3>
        <p class="mt-[6px] text-meta text-muted">{{ videoAvailability(content) }}</p>
      </div>

      <div
        class="content-row-actions flex shrink-0 items-center gap-2 max-[760px]:col-start-3 max-[760px]:justify-self-end"
      >
        <NButton
          class="preview-button size-[42px]! max-[760px]:hidden!"
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

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .content-row {
    @apply flex items-center gap-[18px] border-b border-line px-6 py-[18px] transition-colors;
    @apply duration-[140ms] ease-[ease] last:rounded-b-[11px] last:border-b-0;

    @variant max-[760px] {
      @apply grid grid-cols-[20px_88px_minmax(0,1fr)] gap-3 px-5;
    }

    @variant max-[440px] {
      @apply grid-cols-[20px_72px_minmax(0,1fr)] gap-[10px] px-[14px];
    }
  }

  .content-row.checked {
    @apply bg-[color-mix(in_srgb,var(--accent-soft)_45%,var(--panel))];
  }

  .content-thumbnail {
    @apply relative aspect-video w-[126px] shrink-0 overflow-hidden rounded-[6px] border-0 p-0;

    @variant max-[760px] {
      @apply row-span-2 w-[88px];
    }

    @variant max-[440px] {
      @apply w-[72px];
    }
  }
}
</style>
