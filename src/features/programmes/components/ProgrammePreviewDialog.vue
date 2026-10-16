<script setup lang="ts">
import { computed, onBeforeUnmount, ref, shallowRef, useTemplateRef, watch } from 'vue'
import { NButton, NModal, NSpin } from 'naive-ui'

import { usePlatform } from '@/shared/platform/usePlatform'
import { LatestRequest } from '@/shared/utils/latest-request'
import { errorMessage } from '@/shared/utils/errors'
import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'
import type { ContentRef } from '@shared/contracts/programmes'
import type { PlaybackSession } from '@shared/contracts/media'

const content = defineModel<ProgrammeContent | null>({ required: true })
const props = defineProps<{ quality: Quality; reference: ContentRef | null }>()
const playback = usePlatform().playback
const displayedContent = shallowRef(content.value)
const session = shallowRef<PlaybackSession | null>(null)
const videoPlayer = useTemplateRef('videoPlayer')
const loading = ref(false)
const failed = ref('')
const gate = new LatestRequest()

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
    void playback.close(previous.id).catch(() => {})
  }
}

async function loadPreview() {
  const value = content.value
  const reference = props.reference
  if (!value) {
    return
  }

  const request = gate.begin()
  releaseSession()
  displayedContent.value = value
  failed.value = ''
  loading.value = true
  try {
    if (!reference) {
      throw new Error('节目内容已不可用，请刷新后重试')
    }

    const opened = await playback.open({ ...reference, quality: props.quality }, request.signal)
    if (!request.isCurrent()) {
      await playback.close(opened.id)

      return
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

function updateVisible(show: boolean) {
  if (!show) {
    content.value = null
  }
}

function clearPreview() {
  // Closing pauses immediately; after-leave releases the snapshot/session unless a new preview opened.
  if (!content.value) {
    releaseSession()
    displayedContent.value = null
    loading.value = false
    failed.value = ''
  }
}

watch(
  () => [content.value, props.reference, props.quality] as const,
  ([value]) => {
    if (value) {
      void loadPreview()
    } else {
      gate.cancel()
      videoPlayer.value?.pause()
    }
  },
  { immediate: true },
)

onBeforeUnmount(() => {
  gate.cancel()
  releaseSession()
})
</script>

<template>
  <NModal
    :show="!!content"
    preset="card"
    class="preview-modal"
    :title="displayedContent?.title"
    :bordered="false"
    @update:show="updateVisible"
    @after-leave="clearPreview"
  >
    <ProgrammeVideoPlayer
      v-if="displayedContent && url"
      :key="session?.id"
      ref="videoPlayer"
      :url="url"
      :poster="displayedContent.cover"
      :title="displayedContent.title"
      :variants="variants"
      @error="failed = '这个视频暂时无法播放，请检查网络或换一个日期。'"
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
      @click="loadPreview"
    >
      重试
    </NButton>
  </NModal>
</template>

<style scoped>
/* Naive UI creates the teleported card without this component's scope attribute. */
:global(.preview-modal) {
  width: min(860px, calc(100vw - 32px)) !important;
}
.preview-loading {
  display: grid;
  place-items: center;
  aspect-ratio: 16 / 9;
}
.preview-retry {
  margin-top: 12px;
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
    display: -webkit-box;
    overflow: hidden;
    font-size: 16px;
    line-height: 1.5;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 2;
  }
}
</style>
