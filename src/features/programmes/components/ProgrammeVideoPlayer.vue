<script setup lang="ts">
import { onBeforeUnmount, onMounted, useTemplateRef } from 'vue'
import Artplayer from 'artplayer'

import type { VideoVariant } from '../video'

const props = withDefaults(
  defineProps<{
    url: string
    poster: string | null
    title: string
    variants?: VideoVariant[]
  }>(),
  { variants: () => [] },
)
const emit = defineEmits<{ error: []; ready: [] }>()
const container = useTemplateRef<HTMLDivElement>('container')
let player: Artplayer | undefined

defineExpose({ pause: () => player?.pause() })

onMounted(() => {
  if (!container.value) {
    return
  }

  try {
    // The dialog keys this component by URL so each source owns one instance.
    player = new Artplayer({
      container: container.value,
      url: props.url,
      poster: props.poster || '',
      type: 'mp4',
      lang: 'zh-cn',
      theme: '#dc4f41',
      autoplay: false,
      playsInline: true,
      setting: true,
      quality:
        props.variants.length > 1
          ? props.variants.map((variant) => ({
              html: variant.quality === 'smooth' ? '流畅' : '标准',
              url: variant.url,
              default: variant.url === props.url,
            }))
          : [],
      playbackRate: true,
      pip: true,
      fullscreen: true,
      hotkey: true,
      moreVideoAttr: { controls: false, preload: 'metadata' },
    })
    player.on('video:error', () => emit('error'))
    player.on('video:loadedmetadata', () => emit('ready'))
  } catch {
    emit('error')
  }
})

onBeforeUnmount(() => {
  if (player) {
    try {
      player.pause()
    } finally {
      player.destroy()
    }
  }
})
</script>

<template>
  <div
    ref="container"
    class="programme-player"
    role="region"
    :aria-label="`视频播放器：${title}`"
  />
</template>

<style scoped>
.programme-player {
  aspect-ratio: 16 / 9;
  width: 100%;
  border-radius: 7px;
  background: #08090b;
  --art-font-size: 14px;
}
/* Artplayer creates its controls outside Vue's scoped template. */
@media (width < 480px) {
  .programme-player :deep(.art-video-player) {
    --art-control-height: 44px !important;
  }
  .programme-player :deep(.art-controls .art-control-volume) {
    display: none !important;
  }
  .programme-player :deep(.art-controls .art-control-time) {
    padding-inline: 4px !important;
  }
}
@media (width < 400px) {
  .programme-player :deep(.art-controls .art-control-pip) {
    display: none !important;
  }
  .programme-player :deep(.art-controls .art-control-time) {
    padding-inline: 2px !important;
  }
}
</style>
