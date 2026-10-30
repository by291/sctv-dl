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
// Only the macOS Tauri shell hides its title bar; Windows keeps the native bar.
const overlayTitleBar = platform.kind === 'tauri' && /Macintosh|Mac OS X/i.test(navigator.userAgent)

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
  <div
    class="app-shell"
    :class="{ 'overlay-title-bar': overlayTitleBar }"
  >
    <aside
      class="sidebar"
      data-tauri-drag-region
    >
      <RouterLink
        to="/"
        class="brand"
        aria-label="sctv-dl 首页"
      >
        <span class="brand-icon">
          <Tv :size="22" />
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
            :size="18"
            :stroke-width="1.8"
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
  background: var(--bg);
}
.sidebar {
  --focus: var(--rail-text);

  display: flex;
  height: 100%;
  width: 240px;
  flex-shrink: 0;
  flex-direction: column;
  border-right: 1px solid var(--rail-line);
  background: var(--rail);
  padding: 28px 14px 18px;
  overflow-y: auto;
  overscroll-behavior: none;
  color: var(--rail-text);
}
/* The macOS overlay title bar floats traffic lights over the rail. The extra
   top padding clears them and leaves the sidebar padding as a drag region. */
.app-shell.overlay-title-bar .sidebar {
  padding-top: 52px;
}
.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 0 10px;
  font-size: 23px;
  line-height: 1.2;
  font-weight: 800;
  letter-spacing: -0.7px;
  color: var(--rail-text);
}
.brand-dash {
  color: var(--hero-link);
}
.brand-description {
  display: block;
  margin-top: 5px;
  font-size: 13px;
  font-weight: 400;
  letter-spacing: normal;
  color: var(--rail-muted);
}
.brand-icon {
  display: grid;
  width: 40px;
  height: 40px;
  flex-shrink: 0;
  place-items: center;
  border-radius: var(--radius);
  background: var(--accent);
  color: #fff;
}
.primary-nav {
  display: grid;
  gap: 4px;
  margin-top: 34px;
}
.nav-link {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  border-radius: 5px;
  padding: 11px 12px 11px 14px;
  font-size: 15px;
  font-weight: 500;
  color: var(--rail-muted);
  transition:
    background-color var(--motion-fast) var(--motion-ease),
    color var(--motion-fast) var(--motion-ease);
}
.nav-link.active {
  background: var(--rail-active);
  font-weight: 600;
  color: var(--rail-text);
}
.nav-link.active::before {
  content: '';
  position: absolute;
  top: 9px;
  bottom: 9px;
  left: 0;
  width: 3px;
  border-radius: 2px;
  background: var(--accent);
}
.nav-count {
  position: absolute;
  top: 6px;
  right: 7px;
}
.sidebar-bottom {
  margin-top: auto;
  border-top: 1px solid var(--rail-line);
  padding-top: 16px;
}
.version {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px 0;
  font-size: 12px;
  color: var(--rail-muted);
  font-variant-numeric: tabular-nums;
}
.connection {
  display: flex;
  align-items: center;
  gap: 7px;
  padding-inline: 14px;
  font-size: 12px;
  color: var(--rail-muted);
}
.sidebar .status-dot {
  background: #8dbb9d;
}
.sidebar .status-dot.offline {
  background: #e0a15a;
}
@media (hover: hover) {
  .nav-link:hover {
    background: var(--rail-hover);
    color: var(--rail-text);
  }
  .nav-link.active:hover {
    background: var(--rail-active);
  }
}
@media (width < 1250px) {
  .sidebar {
    width: 220px;
    padding-inline: 12px;
  }
}
@media (width < 1020px) {
  .sidebar {
    width: 204px;
    padding-inline: 8px;
  }
  .brand {
    gap: 9px;
    font-size: 21px;
  }
}
@media (width < 760px) {
  .app-shell {
    flex-direction: column;
  }
  .sidebar {
    z-index: 20;
    height: 62px;
    width: 100%;
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    border-right: 0;
    border-bottom: 1px solid var(--rail-line);
    padding: 0 14px;
  }
  .app-shell.overlay-title-bar .sidebar {
    height: 90px;
    padding-top: 28px;
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
    border-radius: 5px;
  }
  .primary-nav {
    display: flex;
    gap: 2px;
    margin-top: 0;
  }
  .nav-link {
    min-height: 44px;
    flex-direction: column;
    justify-content: center;
    gap: 2px;
    padding: 5px 8px;
    font-size: 11px;
    line-height: 1.3;
    color: var(--rail-muted);
  }
  .nav-link.active {
    background: transparent;
  }
  .nav-link.active::before {
    top: auto;
    right: 8px;
    bottom: 0;
    left: 8px;
    width: auto;
    height: 2px;
  }
  .with-downloads .nav-link {
    flex-direction: column;
    justify-content: center;
    gap: 2px;
    padding: 5px 8px;
    font-size: 11px;
    line-height: 1.3;
  }
  .nav-count {
    top: 0;
    right: 0;
  }
}
@media (width < 380px) {
  .sidebar {
    padding-inline: 10px;
  }
  .brand-icon {
    display: none;
  }
  .with-downloads .nav-link {
    padding-inline: 5px;
  }
}
</style>
