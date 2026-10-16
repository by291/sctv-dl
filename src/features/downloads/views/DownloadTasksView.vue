<script setup lang="ts">
import { NAlert, NButton, NProgress, NSpin } from 'naive-ui'
import { FileVideo } from '@lucide/vue'

import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import StatePanel from '@/shared/components/StatePanel.vue'
import { usePlatform } from '@/shared/platform/usePlatform'

import type { DownloadTask } from '@shared/contracts/downloads'

const downloads = usePlatform().downloads
const tasks = useDownloadTasksStore()

const labels: Record<DownloadTask['state'], string> = {
  queued: '等待下载',
  running: '正在下载',
  completed: '已保存',
  failed: '下载失败',
  cancelled: '已取消',
}
const progressColors: Record<DownloadTask['state'], string> = {
  queued: 'var(--muted)',
  running: 'var(--accent)',
  completed: 'var(--green)',
  failed: 'var(--accent)',
  cancelled: 'var(--muted)',
}

function bytes(value: number): string {
  if (value < 1024) {
    return `${value} B`
  }

  if (value < 1024 * 1024) {
    return `${(value / 1024).toFixed(1)} KiB`
  }

  if (value < 1024 * 1024 * 1024) {
    return `${(value / (1024 * 1024)).toFixed(1)} MiB`
  }

  return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GiB`
}

function progress(task: DownloadTask): number {
  if (task.state === 'completed') {
    return 100
  }

  return Math.min(99, Math.floor((task.receivedBytes / (task.totalBytes || 1)) * 100))
}

function progressStatus(task: DownloadTask): 'success' | 'error' | 'default' {
  if (task.state === 'completed') {
    return 'success'
  }

  return task.state === 'failed' ? 'error' : 'default'
}

function reconnect(): void {
  if (downloads.kind === 'native') {
    void tasks.attach(downloads)
  }
}
</script>

<template>
  <div class="downloads-view">
    <section class="page-heading">
      <div>
        <h1>下载任务</h1>
      </div>
      <span
        v-if="tasks.tasks.length"
        class="download-total"
      >
        共 {{ tasks.tasks.length }} 个任务
      </span>
    </section>

    <NAlert
      v-if="tasks.error"
      type="error"
      class="download-notice"
      title="下载服务暂不可用"
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

    <StatePanel
      v-if="tasks.loading && !tasks.tasks.length"
      loading
    />
    <StatePanel
      v-else-if="!tasks.tasks.length && !tasks.error"
      class="download-empty"
      title="暂无下载任务"
      description="在节目详情中选择内容并下载，任务会显示在这里。"
    />
    <NSpin
      v-if="tasks.loading && tasks.tasks.length"
      class="download-loading"
      size="small"
      aria-label="正在读取下载任务"
    />

    <ul
      v-if="tasks.tasks.length"
      class="download-list"
      aria-label="下载任务列表"
    >
      <li
        v-for="task in tasks.tasks"
        :key="task.id"
        class="download-task"
      >
        <div
          class="download-file-icon"
          aria-hidden="true"
        >
          <FileVideo
            :size="24"
            :stroke-width="1.6"
          />
        </div>
        <div class="download-body">
          <div class="download-heading">
            <h2 class="download-filename">{{ task.filename }}</h2>
            <span class="pill">{{ task.quality === 'standard' ? '标准' : '流畅' }}</span>
          </div>
          <div class="download-state">
            <span :class="`download-state-${task.state}`">{{ labels[task.state] }}</span>
            <span class="download-size">
              {{ bytes(task.receivedBytes) }}
              <template v-if="task.totalBytes !== null">/ {{ bytes(task.totalBytes) }}</template>
              <template v-else>· 总大小未知</template>
            </span>
          </div>
          <NProgress
            v-if="task.totalBytes !== null && task.totalBytes > 0"
            type="line"
            :percentage="progress(task)"
            :show-indicator="false"
            :status="progressStatus(task)"
            :color="progressColors[task.state]"
          />
          <p
            v-if="task.error"
            class="download-error"
            role="alert"
          >
            {{ task.error }}
          </p>
        </div>
        <div class="download-actions">
          <NButton
            v-if="task.state === 'queued' || task.state === 'running'"
            :loading="tasks.pendingActions.includes(task.id)"
            :aria-label="`取消下载${task.filename}`"
            @click="tasks.cancel(task.id)"
          >
            取消
          </NButton>
          <NButton
            v-if="task.state === 'failed' || task.state === 'cancelled'"
            secondary
            :loading="tasks.pendingActions.includes(task.id)"
            :aria-label="`重试下载${task.filename}`"
            @click="tasks.retry(task.id)"
          >
            重试
          </NButton>
        </div>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.download-total {
  flex-shrink: 0;
  color: var(--muted);
  font-size: 14px;
}
.download-notice,
.download-loading {
  margin-bottom: 20px;
}
.download-service-error {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  overflow-wrap: anywhere;
}
.download-empty {
  border: 1px solid var(--line);
  border-radius: 12px;
  background: var(--panel);
}
.download-list {
  display: grid;
  gap: 16px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.download-task {
  display: grid;
  grid-template-columns: 48px minmax(0, 1fr) auto;
  align-items: center;
  gap: 20px;
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 24px;
  background: var(--panel);
}
.download-file-icon {
  display: grid;
  align-self: start;
  width: 48px;
  height: 48px;
  place-items: center;
  border-radius: 10px;
  background: var(--subtle);
  color: var(--muted);
}
.download-body {
  min-width: 0;
}
.download-heading {
  display: flex;
  align-items: baseline;
  gap: 12px;
}
.download-filename {
  min-width: 0;
  overflow-wrap: anywhere;
  font-size: 16px;
  line-height: 1.6;
  font-weight: 600;
}
.download-state {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 16px;
  margin-block: 8px;
  color: var(--muted);
  font-size: 13px;
  line-height: 1.6;
}
.download-size {
  font-variant-numeric: tabular-nums;
}
.download-state-running,
.download-state-failed,
.download-error {
  color: var(--accent);
}
.download-state-completed {
  color: var(--green);
}
.download-error {
  margin-top: 8px;
  overflow-wrap: anywhere;
  font-size: 13px;
  line-height: 1.6;
}
.download-actions {
  display: flex;
  gap: 8px;
}
.download-actions:empty {
  display: none;
}
@container workspace (width < 720px) {
  .download-task {
    grid-template-columns: 36px minmax(0, 1fr);
    align-items: start;
    gap: 12px;
    padding: 20px;
  }
  .download-file-icon {
    width: 36px;
    height: 36px;
  }
  .download-heading {
    flex-wrap: wrap;
    gap: 4px 8px;
  }
  .download-actions {
    grid-column: 2;
    justify-content: flex-end;
  }
}
@media (width < 760px) {
  .page-heading {
    flex-wrap: wrap;
  }
  .download-task {
    padding: 16px;
  }
  .download-service-error {
    flex-wrap: wrap;
  }
  .download-actions :deep(.n-button),
  .download-service-error :deep(.n-button) {
    min-height: 44px;
  }
}
</style>
