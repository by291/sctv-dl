<script setup lang="ts">
import './styles.css'
import { computed } from 'vue'

import { RouterLink, RouterView, useRoute } from 'vue-router'
import { Tv, Library, Download, Settings2, ArrowUpRight, ChevronRight } from '@lucide/vue'

import { useDownloadStore } from '../features/downloads/store'
import { useProgrammeStore } from '../features/programmes/store'

const route = useRoute()
const downloads = useDownloadStore()
const programmes = useProgrammeStore()

const links = [
  { to: '/', label: '节目库', icon: Library },
  { to: '/downloads', label: '下载任务', icon: Download },
  { to: '/settings', label: '设置', icon: Settings2 },
]
const connectionLabel = computed(() => {
  if (programmes.error) {
    return '连接暂时不可用'
  }

  return programmes.updatedAt ? '已连接节目服务' : '四川电视节目'
})

function isActive(path: string): boolean {
  return path === '/' ? route.path === '/' || route.name === 'programme' : route.path === path
}
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar">
      <RouterLink
        to="/"
        class="brand"
        aria-label="sctv-dl 首页"
      >
        <span class="brand-icon"><Tv :size="23" /></span>
        <!-- prettier-ignore -->
        <span>sctv<span class="brand-dash">-dl</span><small>节目收藏室</small></span>
      </RouterLink>
      <div class="nav-caption">工作空间</div>
      <nav aria-label="主导航">
        <RouterLink
          v-for="link in links"
          :key="link.to"
          :to="link.to"
          :class="[
            'nav-link',
            {
              active: isActive(link.to),
            },
          ]"
        >
          <component
            :is="link.icon"
            :size="19"
            :stroke-width="1.7"
          />
          <span>{{ link.label }}</span>
          <span
            v-if="link.to === '/downloads' && downloads.pending.length"
            class="nav-count"
          >
            {{ downloads.pending.length }}
          </span>
        </RouterLink>
      </nav>
      <div class="sidebar-bottom">
        <div class="sidebar-note">
          <span class="eyebrow">YOUR PERSONAL ARCHIVE</span>
          <p>
            一段节目，
            <br />
            一份值得留下的记忆。
          </p>
          <ArrowUpRight :size="19" />
        </div>
        <div class="version">
          <span class="status-dot" />
          Web · v0.1.0
        </div>
      </div>
    </aside>
    <div class="workspace">
      <header class="topbar">
        <div class="breadcrumb">
          <span>sctv-dl</span>
          <ChevronRight :size="14" />
          <strong>{{ route.meta.title }}</strong>
        </div>
        <div class="connection">
          <span :class="['status-dot', { offline: programmes.error }]" />
          {{ connectionLabel }}
        </div>
      </header>
      <main id="main-content"><RouterView /></main>
      <footer class="app-footer">
        <span>
          sctv-dl
          <span class="footer-separator">/</span>
          为喜欢的节目留一个位置
        </span>
        <span>SC TV · PERSONAL COLLECTION</span>
      </footer>
    </div>
  </div>
</template>
