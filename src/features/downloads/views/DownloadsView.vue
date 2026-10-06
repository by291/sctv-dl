<script setup lang="ts">
import { computed, ref } from 'vue'

import { RouterLink } from 'vue-router'
import { NButton, useMessage } from 'naive-ui'
import { Download, ExternalLink, Trash2, Clock3, ArrowRight, FileVideo } from '@lucide/vue'
import { useClipboard } from '@vueuse/core'

import { useDownloadStore } from '../store'
import StatePanel from '../../../components/StatePanel.vue'
import DownloadTaskRow from '../components/DownloadTaskRow.vue'

const store = useDownloadStore()
const message = useMessage()
const { copy: copyText } = useClipboard({ legacy: true })
const tab = ref<'all' | 'queued' | 'handed-off'>('all')
const filtered = computed(() =>
  [...store.tasks]
    .reverse()
    .filter(
      (task) =>
        tab.value === 'all' ||
        (tab.value === 'queued' ? task.status !== 'handed-off' : task.status === 'handed-off'),
    ),
)
const handedOff = computed(() => store.tasks.filter((task) => task.status === 'handed-off').length)

async function copy(url: string) {
  try {
    await copyText(url)
    message.success('已复制源视频地址')
  } catch {
    message.error('浏览器不允许复制，请检查剪贴板权限')
  }
}
</script>

<template>
  <section class="page-heading">
    <div>
      <h1>下载任务</h1>
    </div>
    <NButton
      type="primary"
      :loading="store.batchRunning"
      :disabled="!store.pending.length"
      @click="store.startQueued"
    >
      <template #icon><Download :size="17" /></template>
      开始待处理任务
    </NButton>
  </section>

  <div class="download-stats mb-6 grid grid-cols-3 gap-5 max-[760px]:gap-2.5">
    <div class="download-stat">
      <span class="stat-icon soft">
        <FileVideo :size="21" />
      </span>
      <div>
        <strong class="block text-[28px] leading-[1.1] font-semibold max-[760px]:text-2xl">
          {{ store.tasks.length }}
        </strong>
        <span class="mt-1.75 block text-meta text-muted">全部任务</span>
      </div>
    </div>
    <div class="download-stat">
      <span class="stat-icon warm">
        <Clock3 :size="21" />
      </span>
      <div>
        <strong class="block text-[28px] leading-[1.1] font-semibold max-[760px]:text-2xl">
          {{ store.pending.length }}
        </strong>
        <span class="mt-1.75 block text-meta text-muted">待处理</span>
      </div>
    </div>
    <div class="download-stat">
      <span class="stat-icon green">
        <ExternalLink :size="21" />
      </span>
      <div>
        <strong class="block text-[28px] leading-[1.1] font-semibold max-[760px]:text-2xl">
          {{ handedOff }}
        </strong>
        <span class="mt-1.75 block text-meta text-muted">已交给浏览器</span>
      </div>
    </div>
  </div>

  <div class="notice">
    <ExternalLink :size="17" />
    <p>进度与保存位置由浏览器管理；批量下载可能需要允许下载多个文件。</p>
  </div>

  <div
    v-if="!store.persisted"
    class="notice warning"
  >
    浏览器未允许本地存储，刷新页面后任务列表可能丢失。
  </div>

  <div class="queue-panel rounded-xl border border-line bg-panel">
    <div class="queue-toolbar">
      <div
        class="tabs flex items-center gap-6 max-[760px]:gap-4"
        role="tablist"
        aria-label="任务状态筛选"
      >
        <button
          class="filter-tab queue-tab"
          :class="{ selected: tab === 'all' }"
          role="tab"
          :aria-selected="tab === 'all'"
          @click="tab = 'all'"
        >
          全部任务
          <span class="filter-count">
            {{ store.tasks.length }}
          </span>
        </button>
        <button
          class="filter-tab queue-tab"
          :class="{ selected: tab === 'queued' }"
          role="tab"
          :aria-selected="tab === 'queued'"
          @click="tab = 'queued'"
        >
          待处理
        </button>
        <button
          class="filter-tab queue-tab"
          :class="{ selected: tab === 'handed-off' }"
          role="tab"
          :aria-selected="tab === 'handed-off'"
          @click="tab = 'handed-off'"
        >
          已交给浏览器
        </button>
      </div>
      <NButton
        quaternary
        :disabled="!handedOff"
        @click="store.clearHistory"
      >
        <template #icon><Trash2 :size="15" /></template>
        清理记录
      </NButton>
    </div>
    <StatePanel
      v-if="!filtered.length"
      title="暂无下载任务"
      description="在节目详情页选择内容并加入队列。"
    >
      <RouterLink
        to="/"
        class="empty-link mt-1.5 inline-flex items-center gap-2.25 text-body text-accent"
      >
        浏览节目
        <ArrowRight :size="16" />
      </RouterLink>
    </StatePanel>
    <TransitionGroup
      v-else
      tag="div"
      name="queue"
      class="queue-list relative"
    >
      <DownloadTaskRow
        v-for="task in filtered"
        :key="task.id"
        :task="task"
        :batch-running="store.batchRunning"
        @start="store.start"
        @remove="store.remove"
        @copy="copy"
      />
    </TransitionGroup>
  </div>
</template>

<style scoped>
@reference '../../../styles/global.css';

@layer components {
  .download-stat {
    @apply flex items-center gap-4.5 rounded-[11px] border border-line bg-panel p-5.75;

    @variant max-[760px] {
      @apply gap-2.5 px-2.5 py-3.75;
    }
  }

  .stat-icon {
    @apply flex size-11 items-center justify-center rounded-[10px];

    @variant max-[760px] {
      @apply hidden;
    }
  }

  .stat-icon.soft {
    @apply bg-[#eaf0f9] text-[#7082a7];
  }

  .stat-icon.warm {
    @apply bg-[#fcf3e3] text-[#ba904d];
  }

  .stat-icon.green {
    @apply bg-[#e8f6ef] text-[#439c78];
  }

  .queue-toolbar {
    @apply flex items-center justify-between gap-5 border-b border-line px-6 py-3.25;

    @variant max-[760px] {
      @apply flex-wrap gap-2.5 px-4.5;
    }
  }

  .queue-tab {
    @apply px-0;

    @variant max-[760px] {
      @apply text-meta;
    }
  }

  .queue-tab::after {
    @apply -bottom-3.75;
  }
}
</style>
