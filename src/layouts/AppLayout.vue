<script setup lang="ts">
import './styles.css'
import { computed } from 'vue'

import { RouterLink, RouterView, useRoute } from 'vue-router'
import { Tv, Library, Download, Settings2, ChevronRight } from '@lucide/vue'

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
        <span>sctv<span class="brand-dash">-dl</span><small>电视节目下载</small></span>
      </RouterLink>
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
        <div class="version">Web · v0.1.0</div>
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
    </div>
  </div>
</template>
