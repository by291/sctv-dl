<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { NModal } from 'naive-ui'

import { proxyMediaUrl } from '../../../shared/media'
import { resolveVideo } from '../video'

import type { ProgrammeContent, Quality } from '../types'

const content = defineModel<ProgrammeContent | null>({ required: true })
const props = defineProps<{ quality: Quality }>()
const failed = ref(false)
const url = computed(() => {
  const variant = content.value && resolveVideo(content.value, props.quality)

  return variant ? proxyMediaUrl(variant.url) : ''
})

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
    class="preview-modal"
    :title="content?.title"
    :bordered="false"
    @update:show="updateVisible"
  >
    <video
      v-if="content && url"
      :key="url"
      :src="url"
      controls
      playsinline
      preload="none"
      :poster="content.cover || undefined"
      @error="failed = true"
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
