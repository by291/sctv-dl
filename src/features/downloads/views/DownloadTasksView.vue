<script setup lang="ts">
import { computed, nextTick, onDeactivated, ref, shallowRef } from 'vue'
import { NAlert, NButton, NCheckbox, NModal } from 'naive-ui'

import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import {
  availableDownloadActions,
  isActiveDownload,
} from '@/features/downloads/model/download-actions'
import {
  batchDownloadActions,
  downloadActionLabel,
  downloadActionConfirmation,
} from '@/features/downloads/model/download-action-presentation'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import DownloadTaskCard from '@/features/downloads/components/DownloadTaskCard.vue'
import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import StatePanel from '@/shared/components/StatePanel.vue'
import { usePlatform } from '@/shared/platform/usePlatform'
import { usePageScroll } from '@/shared/navigation/page-scroll'

import type { DownloadTask, DownloadActionRequest } from '@shared/contracts/downloads'
import type { ProgrammeContent } from '@shared/contracts/programmes'
import type { PreviewInput } from '@/features/programmes/model/playback-state'
import type { BatchResult, DownloadTarget } from '@/features/downloads/stores/useDownloadTasksStore'

type Filter = 'all' | 'active' | 'unfinished' | 'completed' | 'missing'

const { pageScrollPosition, scrollPageTo } = usePageScroll()

const downloads = usePlatform().downloads
const tasks = useDownloadTasksStore()
const settings = useSettingsStore()

const filter = ref<Filter>('all')
const selection = ref<string[]>([])
const batchBusy = ref(false)
const batchFeedback = shallowRef<BatchResult | null>(null)
const offsets = new Map<Filter, number>()
const previewContent = ref<ProgrammeContent | null>(null)
const previewInput = shallowRef<PreviewInput | null>(null)
const confirmation = shallowRef<{
  action: DownloadActionRequest['action']
  targets: DownloadTarget[]
  description: string
} | null>(null)

const filterOptions: { label: string; value: Filter }[] = [
  { label: '全部任务', value: 'all' },
  { label: '进行中', value: 'active' },
  { label: '未完成', value: 'unfinished' },
  { label: '已完成', value: 'completed' },
  { label: '文件丢失', value: 'missing' },
]

const filterTabs = computed(() =>
  filterOptions.map((option) => ({
    ...option,
    count: tasks.tasks.filter((task) => matchesFilter(task, option.value)).length,
  })),
)
const filteredTasks = computed(() =>
  tasks.tasks.filter((task) => matchesFilter(task, filter.value)),
)
const selectedTasks = computed(() =>
  filteredTasks.value.filter((task) => selection.value.includes(task.id)),
)
const batchActions = computed(() =>
  batchDownloadActions
    .filter((action) =>
      selectedTasks.value.some((task) => availableDownloadActions(task).includes(action)),
    )
    .map((action) => ({ value: action, label: downloadActionLabel(action, 'batch') })),
)
const allSelected = computed(
  () => filteredTasks.value.length > 0 && selectedTasks.value.length === filteredTasks.value.length,
)

function matchesFilter(task: DownloadTask, value: Filter): boolean {
  switch (value) {
    case 'active':
      return isActiveDownload(task)
    case 'unfinished':
      return !['completed', 'cancelled', 'missing'].includes(task.state)
    case 'completed':
      return task.state === 'completed'
    case 'missing':
      return task.state === 'missing'
    default:
      return true
  }
}

async function changeFilter(value: Filter): Promise<void> {
  if (filter.value === value) {
    return
  }

  offsets.set(filter.value, pageScrollPosition().top)
  filter.value = value
  selection.value = []
  batchFeedback.value = null
  await nextTick()
  scrollPageTo({ top: offsets.get(value) ?? 0 })
}

function select(id: string, checked: boolean): void {
  batchFeedback.value = null
  selection.value = checked
    ? [...new Set([...selection.value, id])]
    : selection.value.filter((value) => value !== id)
}

function batch(action: DownloadActionRequest['action']): void {
  if (batchBusy.value) {
    return
  }

  const targets = selectedTasks.value.map((task) => ({
    taskId: task.id,
    attemptId: task.attemptId,
  }))
  if (!targets.length) {
    return
  }

  const description = downloadActionConfirmation(action, { kind: 'batch', count: targets.length })
  if (description) {
    confirmation.value = { action, targets, description }
  } else {
    void runBatchAction(action, targets)
  }
}

async function runBatchAction(
  action: DownloadActionRequest['action'],
  targets: DownloadTarget[],
): Promise<void> {
  batchBusy.value = true
  batchFeedback.value = null
  try {
    batchFeedback.value = await tasks.runBatch(action, targets)
  } finally {
    batchBusy.value = false
  }
}

async function confirmBatch(): Promise<void> {
  const pending = confirmation.value
  confirmation.value = null
  if (pending) {
    await runBatchAction(pending.action, pending.targets)
  }
}

function play(task: DownloadTask): void {
  previewContent.value = {
    id: task.content.contentId,
    title: task.metadata.title,
    cover: task.metadata.cover,
    video: null,
    smoothVideo: null,
    publishedAt: null,
  }
  previewInput.value = {
    kind: 'download',
    taskId: task.id,
    metadata: task.metadata,
    content: previewContent.value,
  }
}

function selectAllVisible(checked: boolean): void {
  batchFeedback.value = null
  selection.value = checked ? filteredTasks.value.map((task) => task.id) : []
}

function showConfirmation(show: boolean): void {
  if (!show) {
    confirmation.value = null
  }
}

function failureTitle(taskId: string): string {
  return tasks.tasks.find((task) => task.id === taskId)?.metadata.title ?? taskId
}

function reconnect(): void {
  if (downloads.kind === 'native') {
    void tasks.attach(downloads)
  }
}

onDeactivated(() => {
  previewContent.value = null
  confirmation.value = null
})
</script>

<template>
  <div class="downloads-view">
    <section class="page-heading">
      <h1>下载任务</h1>
      <span class="download-total">共 {{ tasks.tasks.length }} 个任务</span>
    </section>
    <NAlert
      v-if="tasks.error"
      type="error"
      class="download-notice"
      title="下载操作未完成"
    >
      <div class="download-service-error">
        <span>{{ tasks.error }}</span>
        <NButton
          secondary
          @click="reconnect"
        >
          重新连接
        </NButton>
      </div>
    </NAlert>
    <NAlert
      v-for="failure in tasks.failures"
      :key="failure.contentId + failure.message"
      type="warning"
      class="download-notice"
    >
      内容 {{ failure.contentId }}：{{ failure.message }}
    </NAlert>
    <div
      class="download-tabs"
      role="group"
      aria-label="筛选下载任务"
    >
      <button
        v-for="tab in filterTabs"
        :key="tab.value"
        type="button"
        class="download-filter"
        :aria-pressed="filter === tab.value"
        @click="changeFilter(tab.value)"
      >
        {{ tab.label }}
        <span class="filter-count">{{ tab.count }}</span>
      </button>
    </div>
    <StatePanel
      v-if="tasks.loading && !tasks.tasks.length"
      loading
    />
    <StatePanel
      v-else-if="!filteredTasks.length && !tasks.error"
      class="download-empty"
      :title="tasks.tasks.length ? '当前筛选下没有任务' : '暂无下载任务'"
      description="在节目详情中选择内容并下载，任务会显示在这里。"
    />
    <section
      v-if="filteredTasks.length"
      class="download-list-panel"
      aria-label="下载任务"
    >
      <div class="download-list-header">
        <NCheckbox
          aria-label="全选"
          :checked="allSelected"
          :indeterminate="selectedTasks.length > 0 && !allSelected"
          @update:checked="selectAllVisible"
        >
          {{ selectedTasks.length ? `已选 ${selectedTasks.length} 项` : '全选' }}
        </NCheckbox>
        <div
          v-if="selectedTasks.length"
          class="batch-actions"
          role="group"
          aria-label="批量管理任务"
        >
          <NButton
            v-for="action in batchActions"
            :key="action.value"
            secondary
            size="small"
            :type="action.value === 'deleteFile' ? 'error' : 'default'"
            :disabled="batchBusy"
            :aria-label="`批量${action.label}`"
            @click="batch(action.value)"
          >
            {{ action.label }}
          </NButton>
          <span
            v-if="!batchActions.length"
            class="download-list-count"
          >
            当前所选任务暂无可用操作
          </span>
        </div>
        <span
          v-else
          class="download-list-count"
        >
          {{ filteredTasks.length }} 个任务
        </span>
      </div>
      <ul
        class="download-list"
        aria-label="下载任务列表"
      >
        <DownloadTaskCard
          v-for="task in filteredTasks"
          :key="task.id"
          :task="task"
          :selected="selection.includes(task.id)"
          :busy="tasks.pendingActions.includes(task.id)"
          @select="select(task.id, $event)"
          @action="tasks.act(task.id, $event)"
          @play="play(task)"
        />
      </ul>
    </section>
    <div
      v-if="batchFeedback"
      class="batch-feedback"
      role="status"
    >
      <p>
        已处理 {{ batchFeedback.applied }} 个，跳过 {{ batchFeedback.skipped }} 个，失败
        {{ batchFeedback.failures.length }} 个。
      </p>
      <ul
        v-if="batchFeedback.failures.length"
        class="batch-failures"
      >
        <li
          v-for="failure in batchFeedback.failures"
          :key="failure.taskId"
        >
          {{ failureTitle(failure.taskId) }}：{{ failure.message }}
        </li>
      </ul>
      <NButton
        size="small"
        quaternary
        @click="batchFeedback = null"
      >
        关闭
      </NButton>
    </div>
    <ProgrammePreviewDialog
      v-if="previewInput"
      v-model="previewContent"
      :input="previewInput"
      :reference="previewInput.metadata.content"
      :quality="settings.quality"
    />
    <NModal
      :show="!!confirmation"
      preset="dialog"
      title="确认批量操作"
      positive-text="确认"
      negative-text="取消"
      @positive-click="confirmBatch"
      @negative-click="confirmation = null"
      @update:show="showConfirmation"
    >
      {{ confirmation?.description }}
    </NModal>
  </div>
</template>

<style scoped>
.download-total {
  color: var(--muted);
  font-size: 13px;
  font-variant-numeric: tabular-nums;
}
.download-notice {
  margin-bottom: 18px;
}
.download-tabs {
  display: flex;
  gap: 24px;
  overflow-x: auto;
  padding: 0;
  margin-bottom: 18px;
  border-bottom: 1px solid var(--line);
}
.download-filter {
  flex-shrink: 0;
  padding: 11px 2px;
  border: 0;
  border-bottom: 2px solid transparent;
  background: transparent;
  color: var(--muted);
  font-size: 14px;
  transition: color var(--motion-fast) var(--motion-ease);
}
.download-filter[aria-pressed='true'] {
  color: var(--accent);
  border-bottom-color: var(--accent);
  font-weight: 600;
}
.download-filter:hover {
  color: var(--text);
}
.download-filter:focus-visible {
  outline-offset: -3px !important;
}
.filter-count {
  margin-left: 7px;
  border-radius: var(--radius-sm);
  background: var(--subtle);
  padding: 1px 6px;
  color: var(--muted);
  font-size: 11px;
  font-variant-numeric: tabular-nums;
}
.download-list-count {
  color: var(--muted);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}
.download-service-error {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 16px;
  justify-content: space-between;
  overflow-wrap: anywhere;
}
.download-list-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 60px;
  gap: 16px;
  padding: 8px 20px;
  border-bottom: 1px solid var(--line);
  background: color-mix(in srgb, var(--subtle) 45%, var(--panel));
}
.download-list-panel {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  overflow: clip;
  background: var(--panel);
}
/* Keep the header height stable; narrow screens scroll actions horizontally. */
.download-list-header > :first-child {
  flex-shrink: 0;
}
.batch-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  overflow-x: auto;
  padding: 4px;
  margin-left: auto;
}
.batch-actions :deep(.n-button) {
  flex-shrink: 0;
}
.batch-feedback {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  width: 100%;
  margin-top: 12px;
  font-size: 12px;
  color: var(--muted);
}
.batch-failures {
  width: 100%;
  max-height: 100px;
  overflow-y: auto;
  padding-left: 20px;
  margin: 0;
  overflow-wrap: anywhere;
}
.download-empty {
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: var(--panel);
}
.download-list {
  display: grid;
  margin: 0;
  padding: 0;
  list-style: none;
}
@media (width < 1100px) {
  .download-list-header {
    padding-inline: 16px;
  }
}
@media (width < 760px) {
  .page-heading {
    flex-wrap: wrap;
  }
  .download-tabs {
    gap: 20px;
  }
  .download-list-header {
    padding-inline: 14px;
    gap: 8px;
  }
  .batch-actions :deep(.n-button) {
    min-height: 44px;
  }
  .download-service-error :deep(.n-button) {
    min-height: 44px;
  }
}
</style>
