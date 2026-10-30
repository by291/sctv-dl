<script setup lang="ts">
import { computed, h, onDeactivated, shallowRef } from 'vue'
import { NButton, NCheckbox, NDropdown, NModal, NProgress } from 'naive-ui'
import {
  Check,
  Ellipsis,
  Play,
  Pause,
  RotateCcw,
  FolderOpen,
  ExternalLink,
  Trash2,
  X,
  ListMinus,
} from '@lucide/vue'

import CoverImage from '@/shared/components/CoverImage.vue'
import { availableDownloadActions } from '@/features/downloads/model/download-actions'
import {
  downloadActionLabel,
  downloadActionConfirmation,
} from '@/features/downloads/model/download-action-presentation'

import type { DownloadTask, DownloadActionRequest } from '@shared/contracts/downloads'

const props = defineProps<{ task: DownloadTask; selected: boolean; busy: boolean }>()
const emit = defineEmits<{
  select: [selected: boolean]
  action: [action: DownloadActionRequest['action']]
  play: []
}>()

const pending = shallowRef<{
  action: DownloadActionRequest['action']
  attemptId: string
  description: string
} | null>(null)

const labels: Record<DownloadTask['state'], string> = {
  queued: '等待下载',
  running: '正在下载',
  pausing: '正在暂停',
  paused: '已暂停',
  interrupted: '等待恢复',
  finalizing: '正在保存',
  completed: '已保存',
  failed: '下载失败',
  cancelled: '已取消',
  missing: '文件已丢失',
}
const actionIcons = {
  pause: Pause,
  resume: Play,
  restart: RotateCcw,
  cancel: X,
  remove: ListMinus,
  deleteFile: Trash2,
  openFile: ExternalLink,
  revealFile: FolderOpen,
}

const actions = computed(() => availableDownloadActions(props.task))
const playable = computed(() => props.task.state === 'completed' && props.task.fileAvailable)
const primaryAction = computed(() =>
  actions.value.find((action) => ['pause', 'resume', 'restart'].includes(action)),
)
const menuOptions = computed(() =>
  actions.value
    .filter((action) => action !== primaryAction.value)
    .map((action) => ({
      key: action,
      label: downloadActionLabel(action),
      icon: () => h(actionIcons[action], { size: 16 }),
      disabled: props.busy,
    })),
)
const showProgress = computed(
  () =>
    !['completed', 'cancelled', 'missing'].includes(props.task.state) &&
    props.task.totalBytes !== null &&
    props.task.totalBytes > 0,
)
const needsRestart = computed(
  () =>
    ['paused', 'interrupted', 'failed'].includes(props.task.state) &&
    props.task.hasPartial &&
    !props.task.canResume,
)
const progress = computed(() =>
  props.task.state === 'completed'
    ? 100
    : Math.min(99, Math.floor((props.task.receivedBytes / (props.task.totalBytes || 1)) * 100)),
)
const status = computed(() =>
  props.task.state === 'completed'
    ? 'success'
    : props.task.state === 'failed'
      ? 'error'
      : 'default',
)
const activeState = computed(() =>
  ['queued', 'running', 'pausing', 'finalizing'].includes(props.task.state),
)

function bytes(value: number): string {
  if (value < 1024) {
    return `${value} B`
  }

  if (value < 1024 ** 2) {
    return `${(value / 1024).toFixed(1)} KiB`
  }

  if (value < 1024 ** 3) {
    return `${(value / 1024 ** 2).toFixed(1)} MiB`
  }

  return `${(value / 1024 ** 3).toFixed(2)} GiB`
}

function requestAction(action: DownloadActionRequest['action']): void {
  if (props.busy || !actions.value.includes(action)) {
    return
  }

  const description = downloadActionConfirmation(action, { kind: 'single', task: props.task })
  if (description) {
    pending.value = { action, attemptId: props.task.attemptId, description }
  } else {
    emit('action', action)
  }
}

function confirmAction(): void {
  const request = pending.value
  pending.value = null
  // A recovered or restarted task must not inherit an older confirmation.
  if (
    request &&
    !props.busy &&
    request.attemptId === props.task.attemptId &&
    actions.value.includes(request.action)
  ) {
    emit('action', request.action)
  }
}

onDeactivated(() => {
  pending.value = null
})
</script>

<template>
  <li
    class="download-task"
    :class="{ 'is-selected': selected }"
  >
    <NCheckbox
      class="task-select"
      :checked="selected"
      :aria-label="`选择任务：${task.filename}`"
      @update:checked="$emit('select', $event)"
    />
    <component
      :is="playable ? 'button' : 'div'"
      class="download-cover"
      :type="playable ? 'button' : undefined"
      :disabled="playable ? busy : undefined"
      :aria-label="playable ? `播放封面：${task.metadata.title}` : undefined"
      @click="playable && !busy && $emit('play')"
    >
      <CoverImage
        :src="task.metadata.cover"
        :alt="task.metadata.title"
      />
      <span
        v-if="playable"
        class="cover-play"
        aria-hidden="true"
      >
        <Play
          :size="24"
          fill="currentColor"
        />
      </span>
    </component>
    <div class="download-body">
      <h2
        class="download-title"
        :title="task.metadata.title"
      >
        {{ task.metadata.title }}
      </h2>
      <p class="download-metadata">
        <span>{{ task.metadata.programmeName }}</span>
        <span>{{ task.metadata.broadcastDate }}</span>
        <span class="quality-label">{{ task.quality === 'standard' ? '标准' : '流畅' }}</span>
      </p>
      <div class="download-state">
        <span
          class="state-label"
          :class="{
            'is-saved': task.state === 'completed',
            'is-error': task.state === 'failed' || task.state === 'missing',
            'is-active': activeState,
          }"
        >
          <Check
            v-if="task.state === 'completed'"
            :size="14"
            aria-hidden="true"
          />
          <span
            v-else
            class="state-dot"
            aria-hidden="true"
          />
          {{ labels[task.state] }}
        </span>
        <span>
          {{ bytes(task.receivedBytes) }}
          <template v-if="task.state !== 'completed'">
            <template v-if="task.totalBytes !== null">/ {{ bytes(task.totalBytes) }}</template>
            <template v-else>· 总大小未知</template>
          </template>
        </span>
        <span
          v-if="showProgress"
          class="download-percentage"
        >
          {{ progress }}%
        </span>
      </div>
      <NProgress
        v-if="showProgress"
        type="line"
        :height="3"
        :percentage="progress"
        :show-indicator="false"
        :status="status"
        color="var(--accent)"
      />
      <p
        v-if="task.error"
        class="download-error"
        role="alert"
      >
        {{ task.error }}
      </p>
      <p
        v-if="needsRestart"
        class="download-hint"
      >
        当前文件不能安全续传，请重新下载。
      </p>
    </div>
    <div class="download-actions">
      <NButton
        v-if="playable"
        secondary
        :disabled="busy"
        :aria-label="`播放本地文件：${task.filename}`"
        @click="$emit('play')"
      >
        <template #icon><Play :size="16" /></template>
        播放
      </NButton>
      <NButton
        v-else-if="primaryAction"
        secondary
        :disabled="busy"
        :aria-label="`${downloadActionLabel(primaryAction)}：${task.filename}`"
        @click="requestAction(primaryAction)"
      >
        <template #icon>
          <component
            :is="actionIcons[primaryAction]"
            :size="16"
          />
        </template>
        {{ downloadActionLabel(primaryAction) }}
      </NButton>
      <NDropdown
        v-if="menuOptions.length"
        trigger="click"
        placement="bottom-end"
        :options="menuOptions"
        @select="requestAction"
      >
        <NButton
          quaternary
          :disabled="busy"
          :aria-label="`更多操作：${task.filename}`"
        >
          <template #icon><Ellipsis :size="20" /></template>
        </NButton>
      </NDropdown>
    </div>
    <NModal
      :show="!!pending"
      preset="dialog"
      :title="pending ? downloadActionLabel(pending.action) : '确认操作'"
      positive-text="确认"
      negative-text="取消"
      @positive-click="confirmAction"
      @negative-click="pending = null"
      @update:show="!$event && (pending = null)"
    >
      {{ pending?.description }}
    </NModal>
  </li>
</template>

<style scoped>
.download-task {
  display: grid;
  grid-template-columns: 18px 148px minmax(0, 1fr) auto;
  align-items: center;
  gap: 18px;
  padding: 18px 20px;
  background: var(--panel);
}
.download-task + .download-task {
  border-top: 1px solid var(--line);
}
.download-task.is-selected {
  background: color-mix(in srgb, var(--accent-soft) 35%, var(--panel));
}
.download-cover {
  position: relative;
  width: 148px;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: 4px;
  border: 0;
  padding: 0;
  background: var(--subtle);
}
.cover-play {
  position: absolute;
  bottom: 8px;
  left: 8px;
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border-radius: 50%;
  border: 1px solid #ffffff33;
  background: color-mix(in srgb, var(--rail) 78%, transparent);
  backdrop-filter: blur(6px);
  color: #fff;
  transition:
    background-color var(--motion-fast) var(--motion-ease),
    transform var(--motion-fast) var(--motion-ease);
}
.download-cover:hover .cover-play {
  background: var(--accent-fill);
  transform: scale(1.05);
}
.download-cover:disabled {
  cursor: wait;
  opacity: 0.6;
}
.download-body {
  min-width: 0;
}
.download-title {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  overflow-wrap: anywhere;
  font-size: 15px;
  line-height: 1.5;
  font-weight: 600;
}
.download-metadata {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 12px;
  margin-top: 5px;
  font-size: 12px;
  color: var(--muted);
}
.quality-label {
  padding: 0 6px;
  border-radius: var(--radius-sm);
  background: var(--subtle);
}
.download-state {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 12px;
  margin-block: 8px 4px;
  font-size: 12px;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}
.state-label {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.state-dot {
  width: 6px;
  height: 6px;
  flex-shrink: 0;
  border-radius: 50%;
  background: currentColor;
}
.is-active {
  color: var(--accent);
}
.is-saved {
  color: var(--green);
}
.is-error,
.download-error {
  color: var(--accent);
}
.download-percentage {
  margin-left: auto;
}
.download-error,
.download-hint {
  margin-top: 6px;
  overflow-wrap: anywhere;
  font-size: 12px;
  line-height: 1.6;
}
.download-hint {
  color: var(--muted);
}
.download-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}
@media (width < 1100px) {
  .download-task {
    grid-template-columns: 18px 128px minmax(0, 1fr);
    gap: 16px;
    padding: 16px;
  }
  .download-cover {
    width: 128px;
  }
  .download-actions {
    grid-column: 3;
    justify-content: flex-end;
  }
}
@media (width < 760px) {
  .download-task {
    grid-template-columns: 18px minmax(0, 1fr) auto;
    gap: 12px;
    padding: 14px;
  }
  .download-cover {
    width: 100%;
    max-width: 128px;
    grid-column: 2;
    grid-row: 1;
  }
  .download-body {
    grid-column: 2 / -1;
    grid-row: 2;
  }
  .download-actions {
    grid-column: 3;
    grid-row: 1;
    flex-direction: column;
    align-items: flex-end;
  }
  .download-actions :deep(.n-button) {
    min-height: 44px;
  }
}
</style>
