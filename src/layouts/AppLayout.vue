<script setup lang="ts">
import { computed } from 'vue'

import { RouterLink, RouterView, useRoute } from 'vue-router'
import { Tv, Library, Settings2 } from '@lucide/vue'

import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { viewTransitionActive } from '@/shared/utils/view-transition'

const route = useRoute()
const programmes = useProgrammeCatalogueStore()

const links = [
  { to: '/', label: '节目库', icon: Library },
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
        <span class="brand-icon">
          <Tv :size="23" />
        </span>
        <!-- prettier-ignore -->
        <span>sctv<span class="brand-dash">-dl</span><small class="brand-description">电视节目下载</small></span>
      </RouterLink>
      <nav
        class="primary-nav"
        aria-label="主导航"
      >
        <RouterLink
          v-for="link in links"
          :key="link.to"
          :to="link.to"
          class="nav-link"
          :class="{ active: isActive(link.to) }"
        >
          <component
            :is="link.icon"
            :size="19"
            :stroke-width="1.7"
          />
          <span>{{ link.label }}</span>
        </RouterLink>
      </nav>
      <div class="sidebar-bottom">
        <div class="version">Web · v0.1.0</div>
      </div>
    </aside>
    <div class="workspace">
      <header
        class="topbar"
        :class="{ offline: programmes.error }"
      >
        <span class="page-location">{{ route.meta.title }}</span>
        <div class="connection">
          <span
            class="status-dot"
            :class="{ offline: programmes.error }"
          />
          {{ connectionLabel }}
        </div>
      </header>
      <main
        id="main-content"
        class="main-content"
      >
        <RouterView v-slot="{ Component, route: currentRoute }">
          <Transition
            name="page"
            :mode="viewTransitionActive ? undefined : 'out-in'"
            :css="!viewTransitionActive"
          >
            <KeepAlive
              include="ProgrammeLibraryView"
              :max="1"
            >
              <component
                :is="Component"
                :key="currentRoute.path"
                class="page-view"
              />
            </KeepAlive>
          </Transition>
        </RouterView>
      </main>
    </div>
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  min-height: 100vh;
}
.sidebar {
  position: sticky;
  top: 0;
  display: flex;
  height: 100vh;
  width: 232px;
  flex-shrink: 0;
  flex-direction: column;
  border-right: 1px solid var(--line);
  background: var(--panel);
  padding: 36px 20px 20px;
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
.nav-link.active {
  background: var(--accent-soft);
  font-weight: 600;
  color: var(--accent);
}
.sidebar-bottom {
  margin-top: auto;
}
.version {
  display: flex;
  align-items: center;
  gap: 8px;
  border-top: 1px solid var(--line);
  padding: 18px 14px 0;
  font-size: 14px;
  color: var(--muted);
}
.workspace {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-direction: column;
}
.topbar {
  display: flex;
  height: 70px;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--line);
  background: var(--panel);
  padding: 0 40px;
}
.page-location {
  font-size: 16px;
  font-weight: 500;
  color: var(--text);
}
.connection {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 14px;
  color: var(--muted);
}
.main-content {
  width: 100%;
  max-width: 1460px;
  flex: 1;
  margin: 0 auto;
  padding: 38px 40px 40px;
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
  .topbar {
    padding-inline: 30px;
  }
  .main-content {
    padding: 30px;
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
  .main-content {
    padding: 28px 24px;
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
    gap: 5px;
    padding: 8px;
    font-size: 14px;
  }
  .topbar {
    display: none;
  }
  .topbar.offline {
    display: flex;
    height: auto;
    min-height: 40px;
    padding: 8px 16px;
  }
  .page-location {
    display: none;
  }
  .main-content {
    padding: 20px 16px 28px;
  }
}
@media (width < 440px) {
  .sidebar {
    padding-inline: 12px;
  }
}
</style>
