import Artplayer from 'artplayer'

import type { Option } from 'artplayer'

import type {
  PlaybackRestore,
  PlaybackSampleReason,
  PlaybackSnapshot,
} from '@/features/programmes/model/playback-state'
import type { PlaybackSession } from '@shared/contracts/media'

interface PlayerOptions {
  readonly url: string
  readonly poster: string | null
  readonly variants: PlaybackSession['sources']
  readonly restore?: PlaybackRestore
  readonly active: boolean
}

interface PlayerEvents {
  error: () => void
  ready: () => void
  snapshot: (value: PlaybackSnapshot, reason: PlaybackSampleReason) => void
}

// Backend retry owns source resolution; Artplayer must not reload the failed URL itself.
class PreviewArtplayer extends Artplayer {
  static RECONNECT_TIME_MAX = 0
}

function detectNativeControls() {
  const video = document.createElement('video') as HTMLVideoElement & {
    webkitSupportsPresentationMode?: (mode: string) => boolean
    webkitSetPresentationMode?: (mode: string) => void
  }

  return {
    pip:
      (!!document.pictureInPictureEnabled && typeof video.requestPictureInPicture === 'function') ||
      (!!video.webkitSupportsPresentationMode?.('picture-in-picture') &&
        typeof video.webkitSetPresentationMode === 'function'),
    fullscreen:
      !!document.fullscreenEnabled ||
      !!(document as Document & { webkitFullscreenEnabled?: boolean }).webkitFullscreenEnabled,
  }
}

function createPlayerOptions(container: HTMLDivElement, options: PlayerOptions): Option {
  return {
    container,
    url: options.url,
    poster: options.poster || '',
    type: 'mp4',
    lang: 'zh-cn',
    theme: '#dc4f41',
    autoplay: false,
    playsInline: true,
    setting: true,
    playbackRate: true,
    ...detectNativeControls(),
    hotkey: true,
    moreVideoAttr: { controls: false, preload: 'metadata' },
  }
}

export function createProgrammePlayerController(options: PlayerOptions, events: PlayerEvents) {
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

    const source = video.currentSrc || video.src || options.url
    const selected = options.variants.find((variant) => {
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
        options.variants.find((variant) => variant.url === options.url)?.quality ??
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

      events.snapshot(value, reason)
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
    if (
      options.restore?.playing &&
      options.active &&
      autoplayAllowed &&
      !disposed &&
      !document.hidden
    ) {
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

  async function switchSource(instance: Artplayer, requestedUrl: unknown): Promise<boolean> {
    const variant = options.variants.find((item) => item.url === requestedUrl)
    if (!variant || qualitySwitch || failed || disposed) {
      return false
    }

    const current = instance.video.currentSrc || instance.video.src || options.url
    if (new URL(current, document.baseURI).href === new URL(variant.url, document.baseURI).href) {
      return true
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

      return true
    } catch {
      if (!failed && !disposed) {
        failedSnapshot = lastUsable
        failed = true
        events.error()
      }
    } finally {
      qualitySwitch = null
    }

    return false
  }

  function configureQualitySelector(instance: Artplayer) {
    if (options.variants.length > 1) {
      const qualities = options.variants.map((variant) => ({
        html: variant.quality === 'smooth' ? '流畅' : '标准',
        url: variant.url,
        default: variant.url === options.url,
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
          if (await switchSource(instance, selection.url)) {
            return selection.html
          }
        },
      })
    }
  }

  function restoreInitialState(instance: Artplayer) {
    if (!initialized && !restoring) {
      const restore = options.restore
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
  }

  function registerMediaEvents(instance: Artplayer) {
    instance.on('video:emptied', beginSourceChange)
    instance.on('video:loadstart', beginSourceChange)
    instance.on('video:error', () => {
      const value = lastUsable ?? capture()
      failedSnapshot = value?.initialized ? value : null
      failed = true
      autoplayAllowed = false
      events.error()
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

      restoreInitialState(instance)

      events.ready()
    })
    instance.on('video:playing', () => {
      if (!options.active || document.hidden || sourceResumeRevoked || failed || disposed) {
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
  }

  function mount(container: HTMLDivElement) {
    try {
      // The dialog keys its component by session so each preview owns one instance.
      const instance = new PreviewArtplayer(createPlayerOptions(container, options))
      player = instance
      document.addEventListener('visibilitychange', visibilityChanged)

      configureQualitySelector(instance)
      registerMediaEvents(instance)
    } catch {
      events.error()
    }
  }

  function dispose() {
    disposed = true
    document.removeEventListener('visibilitychange', visibilityChanged)
    if (player) {
      try {
        player.pause()
      } finally {
        player.destroy()
      }
    }
  }

  return { mount, pause, capture, dispose }
}
