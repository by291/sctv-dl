import { computed, onBeforeUnmount, onDeactivated, ref, shallowRef, watch } from 'vue'

import { usePlatform } from '@/shared/platform/usePlatform'
import { LatestRequest } from '@/shared/utils/latest-request'
import { errorMessage } from '@/shared/utils/errors'
import { useHistoryStore } from '@/features/history/stores/useHistoryStore'
import { usePlaybackHistory } from '@/features/programmes/composables/usePlaybackHistory'

import type { Ref } from 'vue'
import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type {
  PlaybackRestore,
  PlaybackSampleReason,
  PlaybackSnapshot,
  PreviewInput,
} from '@/features/programmes/model/playback-state'
import type { Quality } from '@/shared/media/video-quality'
import type { ContentRef } from '@shared/contracts/programmes'
import type { PlaybackSession } from '@shared/contracts/media'

interface PreviewOptions {
  readonly quality: Quality
  readonly reference: ContentRef | null
  readonly input?: PreviewInput | null
}

interface PreviewPlayer {
  capture: () => PlaybackSnapshot | null
  pause: () => void
}

interface PreviewOwner {
  reference: ContentRef | null
  localTaskId: string | null
  quality: Quality
  history: ReturnType<typeof usePlaybackHistory> | null
  unregisterCapture: (() => void) | null
  lastSnapshot: PlaybackSnapshot | null
  playbackIntentVersion: number
}

export function useProgrammePreview(
  content: Ref<ProgrammeContent | null>,
  options: PreviewOptions,
  videoPlayer: Readonly<Ref<PreviewPlayer | null>>,
) {
  const platform = usePlatform()
  const historyStore = useHistoryStore()
  const displayedContent = shallowRef(content.value)
  const session = shallowRef<PlaybackSession | null>(null)
  const loading = ref(false)
  const failed = ref('')
  const qualityNotice = ref('')
  const hidden = ref(document.hidden)
  const restore = shallowRef<PlaybackRestore>({ positionMs: 0, speed: 1, playing: false })
  const gate = new LatestRequest()
  const owner = shallowRef<PreviewOwner | null>(null)

  const historyWarning = computed(() => owner.value?.history?.warning.value ?? '')
  const url = computed(
    () =>
      session.value?.sources.find((source) => source.quality === session.value?.selectedQuality)
        ?.url ||
      session.value?.sources[0]?.url ||
      '',
  )
  const variants = computed(() => session.value?.sources || [])

  function releaseSession() {
    const previous = session.value
    session.value = null
    if (previous) {
      // Closing is best effort; the backend also owns platform teardown.
      void platform.playback.close(previous.id).catch(() => {})
    }
  }

  function receiveSnapshot(value: PlaybackSnapshot, reason: PlaybackSampleReason) {
    const current = owner.value
    if (!current || failed.value || !value.initialized) {
      return
    }

    current.lastSnapshot = value
    current.history?.update(value, reason)
  }

  function capture(current: PreviewOwner) {
    if (owner.value === current && !failed.value) {
      const value = videoPlayer.value?.capture()
      if (value?.initialized) {
        current.lastSnapshot = value
        current.history?.update(value, 'state')
      }
    }

    return current.lastSnapshot
  }

  function captureAndSave(current: PreviewOwner) {
    capture(current)

    return current.history?.captureAndSave() ?? Promise.resolve()
  }

  function disposeOwner() {
    const previous = owner.value
    if (previous) {
      // Capture synchronously while this player still belongs to the departing owner.
      void captureAndSave(previous)
      previous.unregisterCapture?.()
      void previous.history?.dispose()
    }

    owner.value = null
    releaseSession()
  }

  async function loadPreview(retry = false) {
    const current = owner.value
    if (!current || !content.value) {
      return
    }

    // Cancellation stops cooperative adapters; the request identity also rejects late completions.
    const request = gate.begin()
    const playbackIntentVersion = current.playbackIntentVersion
    const retryState = retry ? current.lastSnapshot : null
    releaseSession()
    failed.value = ''
    loading.value = true
    qualityNotice.value = ''
    try {
      if (!current.reference) {
        throw new Error('节目内容已不可用，请刷新后重试')
      }

      const initial = current.history
        ? await current.history.ready
        : { positionMs: 0, speed: 1, playing: false }
      if (!request.isCurrent()) {
        return
      }

      const opened = current.localTaskId
        ? await openLocal(current.localTaskId, request.signal)
        : await platform.playback.open(
            { ...current.reference, quality: retryState?.quality ?? current.quality },
            request.signal,
          )
      if (!request.isCurrent()) {
        await platform.playback.close(opened.id)

        return
      }

      restore.value = {
        positionMs: retryState?.positionMs ?? initial.positionMs,
        speed: retryState?.speed ?? initial.speed,
        playing:
          !!retryState?.playing &&
          current.playbackIntentVersion === playbackIntentVersion &&
          !document.hidden &&
          !!content.value,
      }
      const requestedQuality = retryState?.quality ?? current.quality
      if (opened.selectedQuality !== requestedQuality) {
        qualityNotice.value = `所选画质暂不可用，已使用${opened.selectedQuality === 'smooth' ? '流畅' : '标准'}画质。`
      }

      session.value = opened
    } catch (cause) {
      if (request.isCurrent()) {
        failed.value = errorMessage(cause)
      }
    } finally {
      if (request.isCurrent()) {
        loading.value = false
      }
    }
  }

  function startPreview(value: ProgrammeContent) {
    gate.cancel()
    disposeOwner()
    const pinned = options.input
    displayedContent.value = { ...(pinned?.content ?? value) }
    const current: PreviewOwner = {
      localTaskId: pinned?.kind === 'download' ? pinned.taskId : null,
      reference: pinned
        ? { ...pinned.metadata.content }
        : options.reference
          ? { ...options.reference }
          : null,
      quality: options.quality,
      history: null,
      unregisterCapture: null,
      lastSnapshot: null,
      playbackIntentVersion: 0,
    }
    owner.value = current
    if (pinned) {
      current.history = usePlaybackHistory(
        platform.history,
        { ...pinned.metadata, content: { ...pinned.metadata.content } },
        () => capture(current),
      )
      current.unregisterCapture = historyStore.registerCapture(() => captureAndSave(current))
    }

    void loadPreview()
  }

  async function openLocal(taskId: string, signal: AbortSignal): Promise<PlaybackSession> {
    if (platform.downloads.kind !== 'native') {
      throw new Error('本地播放仅在桌面版可用')
    }

    return platform.downloads.openPlayback(taskId, signal)
  }

  function mediaError() {
    const current = owner.value
    if (current) {
      // Media errors can set paused before their event; retain the last usable intent.
      const value = videoPlayer.value?.capture()
      if (value?.initialized) {
        current.lastSnapshot = { ...value, playing: current.lastSnapshot?.playing ?? value.playing }
        current.history?.update(current.lastSnapshot, 'state')
      }
    }

    failed.value = '这个视频暂时无法播放，请检查网络或换一个日期。'
    videoPlayer.value?.pause()
  }

  function pausePreview() {
    const current = owner.value
    if (current) {
      void captureAndSave(current)
      current.playbackIntentVersion++
      if (current.lastSnapshot) {
        current.lastSnapshot = { ...current.lastSnapshot, playing: false }
      }
    }

    restore.value = { ...restore.value, playing: false }
    videoPlayer.value?.pause()
  }

  function retryHistory() {
    return owner.value?.history?.retry()
  }

  function mediaReady() {
    failed.value = ''
  }

  function updateVisible(show: boolean) {
    if (!show) {
      content.value = null
    }
  }

  function clearPreview() {
    // Leave callbacks from an older modal cannot release a newly opened preview.
    if (!content.value) {
      // Keep the player mounted until the modal commits its leave transition.
      disposeOwner()
      displayedContent.value = null
      loading.value = false
      failed.value = ''
    }
  }

  function visibilityChanged() {
    hidden.value = document.hidden
    if (hidden.value) {
      pausePreview()
    }
  }

  function deactivate() {
    // A retained tab leaves without a modal animation, so it must release its owner here.
    gate.cancel()
    pausePreview()
    disposeOwner()
    displayedContent.value = null
  }

  document.addEventListener('visibilitychange', visibilityChanged)

  watch(
    () => [content.value, options.input] as const,
    ([value]) => {
      if (value) {
        startPreview(value)
      } else {
        gate.cancel()
        pausePreview()
      }
    },
    { immediate: true },
  )

  onDeactivated(deactivate)
  onBeforeUnmount(() => {
    document.removeEventListener('visibilitychange', visibilityChanged)
    gate.cancel()
    disposeOwner()
  })

  return {
    displayedContent,
    session,
    loading,
    failed,
    qualityNotice,
    hidden,
    restore,
    historyWarning,
    url,
    variants,
    receiveSnapshot,
    mediaError,
    mediaReady,
    loadPreview,
    retryHistory,
    updateVisible,
    clearPreview,
  }
}
