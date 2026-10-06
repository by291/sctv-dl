<script setup lang="ts">
import { onBeforeUnmount, onMounted, useTemplateRef } from 'vue'
import Artplayer from 'artplayer'

const props = defineProps<{ url: string; poster: string | null; title: string }>()
const emit = defineEmits<{ error: [] }>()
const container = useTemplateRef<HTMLDivElement>('container')
let player: Artplayer | undefined

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
      playbackRate: true,
      pip: true,
      fullscreen: true,
      hotkey: true,
      moreVideoAttr: { controls: false, preload: 'metadata' },
    })
    player.on('video:error', () => emit('error'))
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
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #08090b;
  border-radius: 7px;
  --art-font-size: 14px;
}

/* Keep playback, speed, and fullscreen controls reachable in narrow previews. */
@media (max-width: 480px) {
  .programme-player :deep(.art-video-player) {
    --art-control-height: 44px;
  }

  .programme-player :deep(.art-video-player .art-controls .art-control-volume) {
    display: none;
  }

  .programme-player :deep(.art-video-player .art-controls .art-control-time) {
    padding: 0 4px;
  }
}

@media (max-width: 400px) {
  .programme-player :deep(.art-video-player .art-controls .art-control-pip) {
    display: none;
  }

  .programme-player :deep(.art-video-player .art-controls .art-control-time) {
    padding: 0 2px;
  }
}
</style>
