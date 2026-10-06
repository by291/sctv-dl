<script setup lang="ts">
import { computed } from 'vue'
import { NButton } from 'naive-ui'
import { CircleCheck, CircleAlert, Clock3, Copy, Trash2, FileVideo } from '@lucide/vue'

import type { DownloadTask } from '../schema'

const props = defineProps<{ task: DownloadTask; batchRunning: boolean }>()
const emit = defineEmits<{ start: [id: string]; remove: [id: string]; copy: [url: string] }>()

const statusInfo = {
  queued: { label: '等待下载', action: '下载', icon: Clock3 },
  checking: { label: '检查视频…', action: '下载', icon: Clock3 },
  'handed-off': { label: '已交给浏览器', action: '再次下载', icon: CircleCheck },
  failed: { label: '暂时失败', action: '重试', icon: CircleAlert },
} satisfies Record<DownloadTask['status'], { label: string; action: string; icon: typeof Clock3 }>
const status = computed(() => statusInfo[props.task.status])
</script>

<template>
  <article class="queue-row">
    <div class="file-icon">
      <FileVideo
        :size="25"
        :stroke-width="1.5"
      />
    </div>

    <div class="queue-info">
      <h3>{{ task.title }}</h3>
      <p>
        {{ task.programme }}
        <span>·</span>
        {{ task.date }}
        <span>·</span>
        {{ task.quality === 'standard' ? '标准' : '流畅' }}
        <span>·</span>
        MP4
      </p>
      <p
        v-if="task.error"
        class="task-error"
      >
        {{ task.error }}
      </p>
    </div>

    <span :class="['task-status', task.status]">
      <component
        :is="status.icon"
        :size="14"
      />
      {{ status.label }}
    </span>

    <div class="queue-actions">
      <NButton
        :loading="task.status === 'checking'"
        :disabled="batchRunning"
        :type="task.status === 'handed-off' ? 'default' : 'primary'"
        size="small"
        @click="emit('start', task.id)"
      >
        {{ status.action }}
      </NButton>
      <NButton
        quaternary
        circle
        aria-label="复制源视频地址"
        @click="emit('copy', task.url)"
      >
        <Copy :size="15" />
      </NButton>
      <NButton
        quaternary
        circle
        :disabled="task.status === 'checking'"
        aria-label="移除下载任务"
        @click="emit('remove', task.id)"
      >
        <Trash2 :size="15" />
      </NButton>
    </div>
  </article>
</template>
