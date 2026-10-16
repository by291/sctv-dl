<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { NAlert, NButton, NDrawer, NDrawerContent, NEmpty, NProgress, NSpin } from 'naive-ui'
import { Download } from '@lucide/vue'

import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'

import type { NativeDownloadPort } from '@/shared/platform/ports'
import type { DownloadTask } from '@shared/contracts/downloads'

const props = defineProps<{ downloads: NativeDownloadPort }>()
const tasks = useDownloadTasksStore()
const open = ref(false)

const labels: Record<DownloadTask['state'], string> = {
  queued: '等待下载',
  running: '正在下载',
  completed: '已保存',
  failed: '下载失败',
  cancelled: '已取消',
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

function connect() {
  return tasks.attach(props.downloads)
}

onMounted(() => {
  void connect()
})
onBeforeUnmount(() => {
  tasks.detach()
})
</script>

<template>
  <div class="download-panel">
    <NButton
      secondary
      @click="open = true"
    >
      <template #icon><Download :size="17" /></template>
      下载任务
      <span v-if="tasks.activeCount">· {{ tasks.activeCount }} 进行中</span>
    </NButton>
    <NDrawer
      v-model:show="open"
      width="min(440px, 100vw)"
      placement="right"
    >
      <NDrawerContent
        title="下载任务"
        closable
      >
        <p class="download-description">任务在当前应用中继续下载，切换页面不会中断。</p>
        <NAlert
          v-if="tasks.error"
          type="error"
          class="download-notice"
          title="下载服务暂不可用"
        >
          {{ tasks.error }}
          <NButton
            size="small"
            secondary
            @click="connect"
          >
            重新连接
          </NButton>
        </NAlert>
        <NSpin
          v-if="tasks.loading"
          size="small"
          aria-label="正在读取下载任务"
        />
        <NAlert
          v-for="failure in tasks.failures"
          :key="failure.contentId + failure.message"
          type="warning"
          class="download-notice"
        >
          内容 {{ failure.contentId }}：{{ failure.message }}
        </NAlert>
        <NEmpty
          v-if="!tasks.loading && !tasks.tasks.length && !tasks.error"
          description="暂无下载任务"
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
            <div class="download-heading">
              <strong class="download-filename">{{ task.filename }}</strong>
              <span class="download-quality">
                {{ task.quality === 'standard' ? '标准' : '流畅' }}
              </span>
            </div>
            <div
              class="download-state"
              :class="{ 'download-failed': task.state === 'failed' }"
            >
              <span>{{ labels[task.state] }}</span>
              <span>
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
              :status="task.state === 'failed' ? 'error' : 'default'"
            />
            <p
              v-if="task.error"
              class="download-error"
              role="alert"
            >
              {{ task.error }}
            </p>
            <div class="download-actions">
              <NButton
                v-if="task.state === 'queued' || task.state === 'running'"
                size="small"
                :loading="tasks.pendingActions.includes(task.id)"
                @click="tasks.cancel(task.id)"
              >
                取消
              </NButton>
              <NButton
                v-if="task.state === 'failed' || task.state === 'cancelled'"
                size="small"
                secondary
                :loading="tasks.pendingActions.includes(task.id)"
                @click="tasks.retry(task.id)"
              >
                重试
              </NButton>
            </div>
          </li>
        </ul>
      </NDrawerContent>
    </NDrawer>
  </div>
</template>

<style scoped>
.download-panel {
  display: flex;
  justify-content: flex-end;
  width: 100%;
  max-width: 1460px;
  margin-inline: auto;
  padding: 16px var(--page-gutter) 0;
}
.download-description {
  margin: 0 0 20px;
  color: var(--muted);
  font-size: 14px;
  line-height: 1.6;
}
.download-notice {
  margin-bottom: 16px;
}
.download-list {
  display: grid;
  gap: 14px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.download-task {
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 16px;
  background: var(--panel);
}
.download-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.download-filename {
  min-width: 0;
  overflow-wrap: anywhere;
  font-size: 14px;
  line-height: 1.6;
}
.download-quality {
  flex-shrink: 0;
  border-radius: 5px;
  padding: 2px 7px;
  background: var(--subtle);
  color: var(--muted);
  font-size: 12px;
}
.download-state {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 6px;
  margin-block: 12px 8px;
  color: var(--muted);
  font-size: 12px;
}
.download-failed,
.download-error {
  color: var(--accent);
}
.download-error {
  margin: 10px 0 0;
  overflow-wrap: anywhere;
  font-size: 13px;
  line-height: 1.6;
}
.download-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 12px;
}
.download-actions:empty {
  display: none;
}
@media (width < 760px) {
  .download-panel {
    padding: 12px 16px 0;
  }
}
</style>
