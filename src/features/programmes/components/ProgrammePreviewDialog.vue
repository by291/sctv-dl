<script setup lang="ts">
import { computed, ref, shallowRef, useTemplateRef, watch } from 'vue'
import { NModal } from 'naive-ui'

import { proxyMediaUrl } from '../../../shared/media'
import { getVideoVariants, resolveVideo } from '../video'
import ProgrammeVideoPlayer from './ProgrammeVideoPlayer.vue'

import type { ProgrammeContent, Quality } from '../types'

const content = defineModel<ProgrammeContent | null>({ required: true })
const props = defineProps<{ quality: Quality }>()
const displayedContent = shallowRef(content.value)
const videoPlayer = useTemplateRef('videoPlayer')
const failed = ref(false)
const url = computed(() => {
  const variant = displayedContent.value && resolveVideo(displayedContent.value, props.quality)

  return variant ? proxyMediaUrl(variant.url) : ''
})
const variants = computed(() =>
  displayedContent.value
    ? getVideoVariants(displayedContent.value).map((variant) => ({
        ...variant,
        url: proxyMediaUrl(variant.url),
      }))
    : [],
)

function updateVisible(show: boolean) {
  if (!show) {
    content.value = null
  }
}

function clearPreview() {
  if (!content.value) {
    displayedContent.value = null
  }
}

watch(content, (value) => {
  if (value) {
    displayedContent.value = value
  } else {
    // Pause immediately, but keep the closing dialog's content and height intact.
    videoPlayer.value?.pause()
  }
})

watch(url, () => {
  failed.value = false
})
</script>

<template>
  <NModal
    :show="!!content"
    preset="card"
    class="preview-modal"
    :title="displayedContent?.title"
    :bordered="false"
    @update:show="updateVisible"
    @after-leave="clearPreview"
  >
    <ProgrammeVideoPlayer
      v-if="displayedContent && url"
      :key="url"
      ref="videoPlayer"
      :url="url"
      :poster="displayedContent.cover"
      :title="displayedContent.title"
      :variants="variants"
      @error="failed = true"
      @ready="failed = false"
    />
    <p
      v-if="failed"
      class="preview-error"
      role="alert"
    >
      这个视频暂时无法播放，请检查网络或换一个日期。
    </p>
  </NModal>
</template>

<style scoped>
/* Naive UI creates the teleported card without this component's scope attribute. */
:global(.preview-modal) {
  width: min(860px, calc(100vw - 32px)) !important;
}
.preview-error {
  padding-top: 12px;
  font-size: 14px;
  color: var(--accent);
}
@media (width < 760px) {
  :global(.preview-modal) {
    width: calc(100vw - 16px) !important;
  }
  :global(.preview-modal.n-card > .n-card-header) {
    align-items: flex-start;
    padding: 12px 12px 8px;
  }
  :global(.preview-modal.n-card > .n-card-content) {
    padding: 0 12px 12px;
  }
  :global(.preview-modal .n-card-header__close) {
    width: 44px;
    height: 44px;
    flex-shrink: 0;
    margin-top: -8px;
    margin-right: -8px;
  }
  :global(.preview-modal .n-card-header__main) {
    display: -webkit-box;
    overflow: hidden;
    font-size: 16px;
    line-height: 1.5;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
  }
}
</style>
