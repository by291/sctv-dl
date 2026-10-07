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
    class="preview-modal w-[min(860px,calc(100vw-32px))]!"
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
      class="preview-error pt-3 text-meta text-accent"
      role="alert"
    >
      这个视频暂时无法播放，请检查网络或换一个日期。
    </p>
  </NModal>
</template>
