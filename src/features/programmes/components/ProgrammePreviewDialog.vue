<script setup lang="ts">
import { computed, useTemplateRef } from 'vue'
import { NButton, NModal, NSpin } from 'naive-ui'

import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'
import { useProgrammePreview } from '@/features/programmes/composables/useProgrammePreview'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { PreviewInput } from '@/features/programmes/model/playback-state'
import type { Quality } from '@/shared/media/video-quality'
import type { ContentRef } from '@shared/contracts/programmes'

const content = defineModel<ProgrammeContent | null>({ required: true })
const props = defineProps<{
  quality: Quality
  reference: ContentRef | null
  input?: PreviewInput | null
}>()

const videoPlayer = useTemplateRef('videoPlayer')
const contextLabel = computed(() => {
  const metadata = props.input?.metadata

  return metadata ? `${metadata.programmeName} ${metadata.broadcastDate}` : ''
})
const {
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
} = useProgrammePreview(content, props, videoPlayer)
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
      <div class="preview-heading">
        <span
          class="preview-title"
          :title="displayedContent?.title"
        >
          {{ displayedContent?.title }}
        </span>
        <span
          v-if="contextLabel"
          class="preview-context"
        >
          {{ contextLabel }}
        </span>
      </div>
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
      @ready="mediaReady"
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
      @click="retryHistory"
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
:global(.preview-modal .n-card-header) {
  padding: 16px 18px 12px;
}
:global(.preview-modal .n-card-content) {
  padding: 0 18px 18px;
}
:global(.preview-modal .n-card-header__main) {
  min-width: 0;
}
.preview-heading {
  min-width: 0;
}
.preview-title {
  display: block;
  overflow: hidden;
  font-size: 16px;
  line-height: 1.4;
  font-weight: 600;
  letter-spacing: -0.2px;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.preview-context {
  display: block;
  margin-top: 2px;
  overflow: hidden;
  font-size: 12px;
  line-height: 1.5;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.preview-loading {
  display: grid;
  place-items: center;
  aspect-ratio: 16 / 9;
  border-radius: var(--radius);
  background: var(--subtle);
}
.preview-retry {
  margin-top: 12px;
}
.preview-quality-notice {
  padding-top: 12px;
  font-size: 13px;
  line-height: 1.7;
  color: var(--muted);
}
.preview-error {
  padding-top: 12px;
  font-size: 13px;
  line-height: 1.7;
  color: var(--accent);
}
@media (width < 760px) {
  :global(.preview-modal) {
    width: calc(100vw - 16px) !important;
  }
  :global(.preview-modal.n-card > .n-card-header) {
    align-items: flex-start;
    padding: 12px 12px 10px;
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
  .preview-title {
    font-size: 15px;
  }
}
</style>
