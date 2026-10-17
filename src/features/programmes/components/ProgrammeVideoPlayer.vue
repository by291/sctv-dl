<script setup lang="ts">
import { onBeforeUnmount, onMounted, useTemplateRef, watch } from 'vue'
import Artplayer from 'artplayer'

import type {
  PlaybackRestore,
  PlaybackSampleReason,
  PlaybackSnapshot,
} from '@/features/programmes/model/playback-state'
import type { PlaybackSession } from '@shared/contracts/media'

// Backend retry owns source resolution; Artplayer must not reload the failed URL itself.
class PreviewArtplayer extends Artplayer {
  static RECONNECT_TIME_MAX = 0
}

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
let player: Artplayer | undefined

let failed = false
let failedSnapshot: PlaybackSnapshot | null = null
let lastUsable: PlaybackSnapshot | null = null
let initialized = false
let restoring = false
let disposed = false
let autoplayAllowed = true
let pausedByOwner = false
let sourceChange: { metadataReady: boolean } | null = null
let sourceResumeRevoked = false
let qualitySwitch: { playing: boolean } | null = null

function capture(): PlaybackSnapshot | null {
  if (failed) {
    return failedSnapshot
  }

  if (sourceChange) {
    return lastUsable && { ...lastUsable, playing: lastUsable.playing && !pausedByOwner }
  }

  const video = player?.video
  if (!video || !Number.isFinite(video.currentTime)) {
    return null
  }

  const source = video.currentSrc || video.src || props.url
  const selected = props.variants.find((variant) => {
    return new URL(variant.url, document.baseURI).href === new URL(source, document.baseURI).href
  })

  return {
    positionMs: Math.max(0, Math.round(video.currentTime * 1000)),
    durationMs:
      Number.isFinite(video.duration) && video.duration > 0
        ? Math.round(video.duration * 1000)
        : null,
    speed: Number.isFinite(video.playbackRate) && video.playbackRate > 0 ? video.playbackRate : 1,
    quality:
      selected?.quality ??
      props.variants.find((variant) => variant.url === props.url)?.quality ??
      'standard',
    playing: !video.paused,
    ended: video.ended,
    initialized: initialized && !video.seeking && !restoring,
  }
}

function publish(reason: PlaybackSampleReason) {
  if (failed || disposed || sourceChange) {
    return
  }

  const value = capture()
  if (value) {
    if (value.initialized) {
      lastUsable = value
    }

    emit('snapshot', value, reason)
  }
}

function pause() {
  // Once revoked, retry intent cannot revive when visibility returns.
  autoplayAllowed = false
  if (qualitySwitch?.playing || (!qualitySwitch && sourceChange)) {
    sourceResumeRevoked = true
  }

  if (!pausedByOwner) {
    player?.pause()
  }

  pausedByOwner = true
}

function visibilityChanged() {
  if (document.hidden) {
    pause()
  }
}

function beginSourceChange() {
  if (initialized && !sourceChange) {
    // Artplayer replaces the URL before its own metadata listener restores the seek.
    sourceChange = { metadataReady: false }
  }
}

function finishSourceChange() {
  if (sourceChange?.metadataReady && !player?.video.seeking && !failed && !disposed) {
    sourceChange = null
    publish('seek')
  }
}

function finishRestore() {
  if (failed || disposed) {
    return
  }

  restoring = false
  initialized = true
  publish('state')
  if (props.restore?.playing && props.active && autoplayAllowed && !disposed && !document.hidden) {
    const instance = player
    void instance?.video.play().catch(() => {
      // Autoplay policy rejection leaves the restored position usable and paused.
      if (!disposed && instance === player) {
        instance.pause()
        publish('state')
      }
    })
  }
}

watch(
  () => props.active,
  (active) => {
    if (!active) {
      pause()
    }
  },
)
defineExpose({ pause, capture })

onMounted(() => {
  if (!container.value) {
    return
  }

  try {
    const video = document.createElement('video') as HTMLVideoElement & {
      webkitSupportsPresentationMode?: (mode: string) => boolean
      webkitSetPresentationMode?: (mode: string) => void
    }
    const pip =
      (!!document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function') ||
      (!!video.webkitSupportsPresentationMode?.('picture-in-picture') &&
        typeof video.webkitSetPresentationMode === 'function')

    // The dialog keys this component by session so each preview owns one instance.
    const instance = new PreviewArtplayer({
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
      pip,
      fullscreen:
        !!document.fullscreenEnabled ||
        !!(document as Document & { webkitFullscreenEnabled?: boolean }).webkitFullscreenEnabled,
      hotkey: true,
      moreVideoAttr: { controls: false, preload: 'metadata' },
    })
    player = instance
    document.addEventListener('visibilitychange', visibilityChanged)

    if (props.variants.length > 1) {
      const qualities = props.variants.map((variant) => ({
        html: variant.quality === 'smooth' ? '流畅' : '标准',
        url: variant.url,
        default: variant.url === props.url,
      }))
      // Register the complete selector synchronously. Artplayer's quality option creates it
      // on a later timer, so an immediate partial update throws and skips our media listeners.
      instance.controls.update({
        name: 'quality',
        position: 'right',
        index: 10,
        html: (qualities.find((quality) => quality.default) ?? qualities[0])?.html,
        selector: qualities,
        onSelect: async (selection) => {
          const variant = props.variants.find((item) => item.url === selection.url)
          if (!variant || qualitySwitch || failed || disposed) {
            return
          }

          const current = instance.video.currentSrc || instance.video.src || props.url
          if (
            new URL(current, document.baseURI).href === new URL(variant.url, document.baseURI).href
          ) {
            return selection.html
          }

          // Capture before Artplayer pauses and replaces the URL; native reset events are queued.
          const value = capture()
          if (value?.initialized) {
            lastUsable = value
          }

          qualitySwitch = { playing: value?.playing ?? false }
          beginSourceChange()
          try {
            await instance.switchQuality(variant.url)

            return selection.html
          } catch {
            if (!failed && !disposed) {
              failedSnapshot = lastUsable
              failed = true
              emit('error')
            }
          } finally {
            qualitySwitch = null
          }
        },
      })
    }

    instance.on('video:emptied', beginSourceChange)
    instance.on('video:loadstart', beginSourceChange)
    instance.on('video:error', () => {
      const value = lastUsable ?? capture()
      failedSnapshot = value?.initialized ? value : null
      failed = true
      autoplayAllowed = false
      emit('error')
    })
    instance.on('video:loadedmetadata', () => {
      if (failed || disposed) {
        return
      }

      if (sourceChange) {
        sourceChange.metadataReady = true

        return
      }

      // WebKit can defer canplay until a metadata-only preview is explicitly played.
      if (instance.video.paused && !instance.video.seeking) {
        instance.loading.show = false
        instance.mask.show = true
      }

      if (!initialized && !restoring) {
        const restore = props.restore
        instance.video.playbackRate = restore?.speed ?? 1
        const maximum =
          Number.isFinite(instance.video.duration) && instance.video.duration > 0
            ? instance.video.duration
            : Infinity
        const target = Math.min(Math.max(0, (restore?.positionMs ?? 0) / 1000), maximum)
        if (Math.abs(instance.video.currentTime - target) > 0.01) {
          // Assigning currentTime requests a seek; only seeked confirms usable progress.
          restoring = true
          instance.video.currentTime = target
        } else {
          finishRestore()
        }
      }

      emit('ready')
    })
    instance.on('video:playing', () => {
      if (!props.active || document.hidden || sourceResumeRevoked || failed || disposed) {
        sourceResumeRevoked = false
        // A library quality switch can call play after the owner's earlier pause.
        instance.pause()

        return
      }

      pausedByOwner = false
      instance.loading.show = false
      publish('state')
    })
    instance.on('video:seeked', () => {
      if (sourceChange) {
        finishSourceChange()

        return
      }

      if (restoring) {
        finishRestore()
      }

      publish('seek')
    })
    instance.on('video:canplay', () => {
      const pending = sourceChange
      // A zero-position switch may not seek. Let Artplayer's metadata handler run first.
      queueMicrotask(() => {
        if (pending && pending === sourceChange) {
          finishSourceChange()
        }
      })
    })
    instance.on('video:timeupdate', () => publish('progress'))
    instance.on('video:pause', () => {
      if (!instance.video.error) {
        publish('pause')
      }
    })
    instance.on('video:ended', () => publish('ended'))
    instance.on('video:ratechange', () => publish('state'))
  } catch {
    emit('error')
  }
})

onBeforeUnmount(() => {
  disposed = true
  document.removeEventListener('visibilitychange', visibilityChanged)
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
