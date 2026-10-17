<script setup lang="ts">
import {
  computed,
  onBeforeUnmount,
  onDeactivated,
  ref,
  shallowRef,
  useTemplateRef,
  watch,
} from 'vue'
import { NButton, NModal, NSpin } from 'naive-ui'

import { usePlatform } from '@/shared/platform/usePlatform'
import { LatestRequest } from '@/shared/utils/latest-request'
import { errorMessage } from '@/shared/utils/errors'
import { useHistoryStore } from '@/features/history/stores/useHistoryStore'
import { usePlaybackHistory } from '@/features/programmes/composables/usePlaybackHistory'
import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

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

const content = defineModel<ProgrammeContent | null>({ required: true })
const props = defineProps<{
  quality: Quality
  reference: ContentRef | null
  input?: PreviewInput | null
}>()
const platform = usePlatform()
const historyStore = useHistoryStore()
const displayedContent = shallowRef(content.value)
const session = shallowRef<PlaybackSession | null>(null)
const videoPlayer = useTemplateRef('videoPlayer')
const loading = ref(false)
const failed = ref('')
const qualityNotice = ref('')
const hidden = ref(document.hidden)
const restore = shallowRef<PlaybackRestore>({ positionMs: 0, speed: 1, playing: false })
const gate = new LatestRequest()

interface PreviewOwner {
  reference: ContentRef | null
  localTaskId: string | null
  quality: Quality
  history: ReturnType<typeof usePlaybackHistory> | null
  unregister: (() => void) | null
  last: PlaybackSnapshot | null
  intentVersion: number
}
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

  current.last = value
  current.history?.update(value, reason)
}

function capture(current: PreviewOwner) {
  if (owner.value === current && !failed.value) {
    const value = videoPlayer.value?.capture()
    if (value?.initialized) {
      current.last = value
      current.history?.update(value, 'state')
    }
  }

  return current.last
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
    previous.unregister?.()
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

  const request = gate.begin()
  const intentVersion = current.intentVersion
  const retryState = retry ? current.last : null
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
        current.intentVersion === intentVersion &&
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
  const pinned = props.input
  displayedContent.value = { ...(pinned?.content ?? value) }
  const current: PreviewOwner = {
    localTaskId: pinned?.kind === 'download' ? pinned.taskId : null,
    reference: pinned
      ? { ...pinned.metadata.content }
      : props.reference
        ? { ...props.reference }
        : null,
    quality: props.quality,
    history: null,
    unregister: null,
    last: null,
    intentVersion: 0,
  }
  owner.value = current
  if (pinned) {
    current.history = usePlaybackHistory(
      platform.history,
      { ...pinned.metadata, content: { ...pinned.metadata.content } },
      () => capture(current),
    )
    current.unregister = historyStore.registerCapture(() => captureAndSave(current))
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
      current.last = { ...value, playing: current.last?.playing ?? value.playing }
      current.history?.update(current.last, 'state')
    }
  }

  failed.value = '这个视频暂时无法播放，请检查网络或换一个日期。'
  videoPlayer.value?.pause()
}

function pausePreview() {
  const current = owner.value
  if (current) {
    void captureAndSave(current)
    current.intentVersion++
    if (current.last) {
      current.last = { ...current.last, playing: false }
    }
  }

  restore.value = { ...restore.value, playing: false }
  videoPlayer.value?.pause()
}

function updateVisible(show: boolean) {
  if (!show) {
    content.value = null
  }
}

function clearPreview() {
  // Leave callbacks from an older modal cannot release a newly opened preview.
  if (!content.value) {
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

document.addEventListener('visibilitychange', visibilityChanged)

watch(
  () => [content.value, props.input] as const,
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

function deactivate() {
  gate.cancel()
  pausePreview()
  disposeOwner()
  displayedContent.value = null
}

onDeactivated(deactivate)
onBeforeUnmount(() => {
  document.removeEventListener('visibilitychange', visibilityChanged)
  gate.cancel()
  disposeOwner()
})
</script>

<template>
  <NModal
    :show="!!content"
    preset="card"
    class="preview-modal"
    :bordered="false"
    @update:show="updateVisible"
    @after-leave="clearPreview"
  >
    <template #header>
      <span
        class="preview-title"
        :title="displayedContent?.title"
      >
        {{ displayedContent?.title }}
      </span>
    </template>
    <ProgrammeVideoPlayer
      v-if="displayedContent && url"
      :key="session?.id"
      ref="videoPlayer"
      :url="url"
      :poster="displayedContent.cover"
      :title="displayedContent.title"
      :variants="variants"
      :restore="restore"
      :active="!!content && !hidden"
      @snapshot="receiveSnapshot"
      @error="mediaError"
      @ready="failed = ''"
    />
    <div
      v-if="loading"
      class="preview-loading"
      role="status"
      aria-label="正在准备视频"
    >
      <NSpin size="small" />
    </div>
    <p
      v-if="failed"
      class="preview-error"
      role="alert"
    >
      {{ failed }}
    </p>
    <NButton
      v-if="failed"
      secondary
      class="preview-retry"
      @click="loadPreview(true)"
    >
      重试
    </NButton>
    <p
      v-if="qualityNotice"
      class="preview-quality-notice"
      role="status"
    >
      {{ qualityNotice }}
    </p>
    <p
      v-if="historyWarning"
      class="preview-error"
      role="status"
    >
      观看记录保存失败：{{ historyWarning }}
    </p>
    <NButton
      v-if="historyWarning"
      secondary
      class="preview-retry"
      @click="owner?.history?.retry()"
    >
      重试保存记录
    </NButton>
  </NModal>
</template>

<style scoped>
/* Naive UI creates the teleported card without this component's scope attribute. */
:global(.preview-modal) {
  width: min(860px, calc(100vw - 32px)) !important;
}
:global(.preview-modal .n-card-header__main) {
  min-width: 0;
}
.preview-title {
  display: block;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.preview-loading {
  display: grid;
  place-items: center;
  aspect-ratio: 16 / 9;
}
.preview-retry {
  margin-top: 12px;
}
.preview-quality-notice {
  padding-top: 12px;
  font-size: 14px;
  color: var(--muted);
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
    font-size: 16px;
    line-height: 1.5;
  }
}
</style>
