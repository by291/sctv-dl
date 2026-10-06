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
    <div
      class="file-icon grid h-11.5 w-10.5 shrink-0 place-items-center rounded-[7px] border border-line text-[#8993a5]"
    >
      <FileVideo
        :size="25"
        :stroke-width="1.5"
      />
    </div>

    <div class="queue-info min-w-0 flex-1 max-[1020px]:basis-[calc(100%-70px)]">
      <h3 class="text-body leading-[1.8] font-medium wrap-anywhere">{{ task.title }}</h3>
      <p class="mt-1.25 text-meta text-muted [&>span]:px-1.75">
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
        class="task-error mt-1.25 text-meta text-accent"
      >
        {{ task.error }}
      </p>
    </div>

    <Transition
      name="fade"
      mode="out-in"
    >
      <span
        :key="task.status"
        class="task-status"
        :class="task.status"
      >
        <component
          :is="status.icon"
          :size="14"
        />
        {{ status.label }}
      </span>
    </Transition>

    <div class="queue-actions flex items-center gap-1.75 max-[1020px]:ml-auto max-[440px]:gap-0.5">
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

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .task-status {
    @apply flex items-center gap-1.5 text-meta whitespace-nowrap text-muted;

    @variant max-[1020px] {
      @apply ml-13.5;
    }

    @variant max-[440px] {
      @apply ml-0;
    }
  }

  .task-status.handed-off {
    @apply text-success;
  }

  .task-status.failed {
    @apply text-accent;
  }

  .queue-row {
    @apply flex items-center gap-4.5 border-b border-line p-6 last:border-0;

    @variant max-[1250px] {
      @apply gap-3;
    }

    @variant max-[1020px] {
      @apply flex-wrap;
    }

    @variant max-[760px] {
      @apply px-4.5 py-5;
    }
  }
}
</style>
