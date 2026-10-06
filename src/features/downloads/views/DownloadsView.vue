<script setup lang="ts">
import '../styles.css'
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
      <div class="eyebrow">DOWNLOAD QUEUE</div>
      <h1>
        让喜欢的节目，留在本地
        <span class="title-dot">.</span>
      </h1>
      <p>整理你的下载列表，交给浏览器开始保存。</p>
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

  <div class="download-stats">
    <div>
      <span class="stat-icon soft"><FileVideo :size="21" /></span>
      <div>
        <strong>{{ store.tasks.length }}</strong>
        <span>全部任务</span>
      </div>
    </div>
    <div>
      <span class="stat-icon warm"><Clock3 :size="21" /></span>
      <div>
        <strong>{{ store.pending.length }}</strong>
        <span>待处理</span>
      </div>
    </div>
    <div>
      <span class="stat-icon green"><ExternalLink :size="21" /></span>
      <div>
        <strong>{{ handedOff }}</strong>
        <span>已交给浏览器</span>
      </div>
    </div>
  </div>

  <div class="notice">
    <ExternalLink :size="17" />
    <p>
      文件保存、下载进度和取消操作在浏览器下载管理器中查看。批量下载时，浏览器可能会询问是否允许下载多个文件。
    </p>
  </div>

  <div
    v-if="!store.persisted"
    class="notice warning"
  >
    浏览器未允许本地存储，刷新页面后任务列表可能丢失。
  </div>

  <div class="queue-panel">
    <div class="queue-toolbar">
      <div
        class="tabs"
        role="tablist"
        aria-label="任务状态筛选"
      >
        <button
          :class="{ selected: tab === 'all' }"
          role="tab"
          :aria-selected="tab === 'all'"
          @click="tab = 'all'"
        >
          全部任务
          <span>{{ store.tasks.length }}</span>
        </button>
        <button
          :class="{ selected: tab === 'queued' }"
          role="tab"
          :aria-selected="tab === 'queued'"
          @click="tab = 'queued'"
        >
          待处理
        </button>
        <button
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
      title="下载列表空空的"
      description="去节目库挑选一个栏目，把想留下的整期或片段加入这里。"
    >
      <RouterLink
        to="/"
        class="empty-link"
      >
        去发现节目
        <ArrowRight :size="16" />
      </RouterLink>
    </StatePanel>
    <div
      v-else
      class="queue-list"
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
    </div>
  </div>
</template>
