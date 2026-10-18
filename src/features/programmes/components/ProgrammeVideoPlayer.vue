<script setup lang="ts">
import { onBeforeUnmount, onMounted, useTemplateRef, watch } from 'vue'

import { createProgrammePlayerController } from '@/features/programmes/composables/programme-player-controller'

import type {
  PlaybackRestore,
  PlaybackSampleReason,
  PlaybackSnapshot,
} from '@/features/programmes/model/playback-state'
import type { PlaybackSession } from '@shared/contracts/media'

const props = withDefaults(
  defineProps<{
    url: string
    poster: string | null
    title: string
    variants?: PlaybackSession['sources']
    restore?: PlaybackRestore
    active?: boolean
  }>(),
  { variants: () => [], active: true, restore: undefined },
)
const emit = defineEmits<{
  error: []
  ready: []
  snapshot: [value: PlaybackSnapshot, reason: PlaybackSampleReason]
}>()

const container = useTemplateRef<HTMLDivElement>('container')
const controller = createProgrammePlayerController(props, {
  error: () => emit('error'),
  ready: () => emit('ready'),
  snapshot: (value, reason) => emit('snapshot', value, reason),
})

watch(
  () => props.active,
  (active) => {
    if (!active) {
      controller.pause()
    }
  },
)

defineExpose({ pause: controller.pause, capture: controller.capture })

onMounted(() => {
  if (container.value) {
    controller.mount(container.value)
  }
})
onBeforeUnmount(controller.dispose)
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
  container: programme-player / inline-size;
  aspect-ratio: 16 / 9;
  width: 100%;
  border-radius: 7px;
  background: #08090b;
  --art-font-size: 14px;
}
/* Artplayer creates its controls outside Vue's scoped template. */
@container programme-player (width < 480px) {
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
@container programme-player (width < 360px) {
  .programme-player :deep(.art-video-player) {
    --art-padding: 4px;
  }
  .programme-player :deep(.art-controls .art-control-pip) {
    display: none !important;
  }
  .programme-player :deep(.art-controls .art-control-time) {
    font-size: 12px;
    padding-inline: 2px !important;
  }
}
</style>
