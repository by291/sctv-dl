<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, watch } from 'vue'

import { RouterLink, useRouter } from 'vue-router'
import { NBadge } from 'naive-ui'
import { Tv, Library, Download, Settings2, History } from '@lucide/vue'

import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import NavigationTabView from '@/layouts/NavigationTabView.vue'
import { navigationTab } from '@/shared/navigation/navigation-tab'
import type { NavigationTab } from '@/shared/navigation/navigation-tab'
import { usePlatform } from '@/shared/platform/usePlatform'

const router = useRouter()
const route = computed(() => router.currentRoute.value)
const activeTab = computed(() => navigationTab(route.value.path))
const destinations = reactive<Record<NavigationTab, string>>({
  '/': '/',
  '/history': '/history',
  '/downloads': '/downloads',
  '/settings': '/settings',
})
watch(
  route,
  (value) => {
    destinations[navigationTab(value.path)] = value.fullPath
  },
  { immediate: true, flush: 'sync' },
)
const platform = usePlatform()
const programmes = useProgrammeCatalogueStore()
const tasks = useDownloadTasksStore()
const downloads = platform.downloads
const appVersion = import.meta.env.APP_VERSION

const links = [
  { to: '/', label: '节目库', icon: Library },
  { to: '/history', label: '观看历史', icon: History },
  ...(downloads.kind === 'native' ? [{ to: '/downloads', label: '下载任务', icon: Download }] : []),
  { to: '/settings', label: '设置', icon: Settings2 },
]
const downloadNavigationLabel = computed(() =>
  tasks.activeCount ? `下载任务，${tasks.activeCount} 个进行中` : '下载任务',
)
const connectionLabel = computed(() => {
  return programmes.serviceStatus.label
})

function isActive(path: string): boolean {
  return activeTab.value === path
}

// The shell keeps progress observation alive while individual pages mount and unmount.
onMounted(() => {
  if (downloads.kind === 'native') {
    void tasks.attach(downloads)
  }
})

onBeforeUnmount(() => {
  if (downloads.kind === 'native') {
    tasks.detach()
  }
})
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar">
      <RouterLink
        to="/"
        class="brand"
        aria-label="sctv-dl 首页"
      >
        <span class="brand-icon">
          <Tv :size="23" />
        </span>
        <!-- prettier-ignore -->
        <span>sctv<span class="brand-dash">-dl</span><small class="brand-description">电视节目下载</small></span>
      </RouterLink>
      <nav
        class="primary-nav"
        :class="{ 'with-downloads': downloads.kind === 'native' }"
        aria-label="主导航"
      >
        <RouterLink
          v-for="link in links"
          :key="link.to"
          :to="destinations[navigationTab(link.to)]"
          class="nav-link"
          :class="{ active: isActive(link.to) }"
          :aria-label="link.to === '/downloads' ? downloadNavigationLabel : undefined"
        >
          <component
            :is="link.icon"
            :size="19"
            :stroke-width="1.7"
          />
          <span>{{ link.label }}</span>
          <NBadge
            v-if="link.to === '/downloads' && tasks.activeCount"
            class="nav-count"
            :value="tasks.activeCount"
            :max="99"
            aria-hidden="true"
          />
        </RouterLink>
      </nav>
      <div class="sidebar-bottom">
        <div
          class="connection"
          role="status"
        >
          <span
            class="status-dot"
            :class="{ offline: programmes.serviceStatus.error }"
            aria-hidden="true"
          />
          {{ connectionLabel }}
        </div>
        <div class="version">
          {{ platform.kind === 'tauri' ? 'Desktop' : 'Web' }} · v{{ appVersion }}
        </div>
      </div>
    </aside>
    <KeepAlive :max="4">
      <NavigationTabView
        :key="activeTab"
        :route="route"
        :warning="programmes.serviceStatus.error ? connectionLabel : ''"
      />
    </KeepAlive>
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  height: 100dvh;
  overflow: hidden;
}
.sidebar {
  display: flex;
  height: 100%;
  width: 232px;
  flex-shrink: 0;
  flex-direction: column;
  border-right: 1px solid var(--line);
  background: var(--panel);
  padding: 36px 20px 20px;
  overflow-y: auto;
  overscroll-behavior: none;
}
.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 0 11px;
  font-size: 24px;
  line-height: 1.2;
  font-weight: 800;
  letter-spacing: -0.8px;
}
.brand-dash {
  color: var(--accent);
}
.brand-description {
  display: block;
  margin-top: 6px;
  font-size: 14px;
  font-weight: 400;
  letter-spacing: normal;
  color: var(--muted);
}
.brand-icon {
  display: grid;
  width: 42px;
  height: 42px;
  flex-shrink: 0;
  place-items: center;
  border-radius: 12px;
  background: var(--accent);
  color: white;
}
.primary-nav {
  display: grid;
  gap: 8px;
  margin-top: 40px;
}
.nav-link {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  border-radius: 8px;
  padding: 13px 15px;
  font-size: 16px;
  font-weight: 500;
  color: var(--muted);
  transition:
    background 150ms ease,
    color 150ms ease;
}
.nav-count {
  position: absolute;
  top: 7px;
  right: 8px;
}
.nav-link.active {
  background: var(--accent-soft);
  font-weight: 600;
  color: var(--accent);
}
.sidebar-bottom {
  margin-top: auto;
  border-top: 1px solid var(--line);
  padding-top: 18px;
}
.version {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px 0;
  font-size: 13px;
  color: var(--muted);
}
.connection {
  display: flex;
  align-items: center;
  gap: 7px;
  padding-inline: 14px;
  font-size: 12px;
  color: var(--muted);
}
@media (hover: hover) {
  .nav-link:hover {
    background: var(--subtle);
  }
  .nav-link.active:hover {
    background: var(--accent-soft);
  }
}
@media (width < 1250px) {
  .sidebar {
    width: 216px;
    padding-inline: 15px;
  }
}
@media (width < 1020px) {
  .sidebar {
    width: 200px;
    padding-inline: 10px;
  }
  .brand {
    gap: 8px;
    font-size: 21px;
  }
}
@media (width < 760px) {
  .app-shell {
    flex-direction: column;
  }
  .sidebar {
    z-index: 20;
    height: 64px;
    width: 100%;
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    border-right: 0;
    border-bottom: 1px solid var(--line);
    padding: 0 16px;
  }
  .brand {
    min-height: 44px;
    gap: 8px;
    padding-inline: 0;
    font-size: 19px;
  }
  .brand-description,
  .sidebar-bottom {
    display: none;
  }
  .brand-icon {
    width: 32px;
    height: 32px;
    border-radius: 10px;
  }
  .primary-nav {
    display: flex;
    gap: 4px;
    margin-top: 0;
  }
  .nav-link {
    min-height: 44px;
    flex-direction: column;
    justify-content: center;
    gap: 3px;
    padding: 6px 8px;
    font-size: 12px;
    line-height: 1.3;
  }
  .with-downloads .nav-link {
    flex-direction: column;
    justify-content: center;
    gap: 3px;
    padding: 6px 9px;
    font-size: 12px;
    line-height: 1.3;
  }
  .nav-count {
    top: 0;
    right: 0;
  }
}
@media (width < 440px) {
  .sidebar {
    padding-inline: 12px;
  }
  .brand-icon {
    display: none;
  }
  .with-downloads .nav-link {
    padding-inline: 5px;
  }
}
</style>
