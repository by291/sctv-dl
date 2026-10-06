<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { NModal } from 'naive-ui'

import { proxyMediaUrl } from '../../../shared/media'
import { getVideoVariants, resolveVideo } from '../video'
import ProgrammeVideoPlayer from './ProgrammeVideoPlayer.vue'

import type { ProgrammeContent, Quality } from '../types'

const content = defineModel<ProgrammeContent | null>({ required: true })
const props = defineProps<{ quality: Quality }>()
const failed = ref(false)
const url = computed(() => {
  const variant = content.value && resolveVideo(content.value, props.quality)

  return variant ? proxyMediaUrl(variant.url) : ''
})
const variants = computed(() =>
  content.value
    ? getVideoVariants(content.value).map((variant) => ({
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

watch(url, () => {
  failed.value = false
})
</script>

<template>
  <NModal
    :show="!!content"
    preset="card"
    class="preview-modal w-[min(860px,calc(100vw-32px))]!"
    :title="content?.title"
    :bordered="false"
    @update:show="updateVisible"
  >
    <ProgrammeVideoPlayer
      v-if="content && url"
      :key="url"
      :url="url"
      :poster="content.cover"
      :title="content.title"
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
