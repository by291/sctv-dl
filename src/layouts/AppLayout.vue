<script setup lang="ts">
import { computed } from 'vue'

import { RouterLink, RouterView, useRoute } from 'vue-router'
import { Tv, Library, Download, Settings2 } from '@lucide/vue'

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
  <div class="app-shell flex min-h-screen max-[760px]:flex-col">
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
        <span>sctv<span class="brand-dash text-accent">-dl</span><small class="mt-1.5 block text-meta font-normal tracking-normal text-muted max-[760px]:hidden">电视节目下载</small></span>
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
          <span
            v-if="link.to === '/downloads' && downloads.pending.length"
            class="nav-count"
          >
            {{ downloads.pending.length }}
          </span>
        </RouterLink>
      </nav>
      <div class="sidebar-bottom mt-auto max-[760px]:hidden">
        <div
          class="version flex items-center gap-2 border-t border-line px-[14px] pt-[18px] text-meta text-muted"
        >
          Web · v0.1.0
        </div>
      </div>
    </aside>
    <div class="workspace flex min-w-0 flex-1 flex-col">
      <header class="topbar">
        <span class="page-location text-body font-medium text-main">{{ route.meta.title }}</span>
        <div class="connection flex items-center gap-[7px] text-meta text-muted">
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
            mode="out-in"
          >
            <div
              :key="currentRoute.path"
              class="page-view"
            >
              <component :is="Component" />
            </div>
          </Transition>
        </RouterView>
      </main>
    </div>
  </div>
</template>

<style scoped>
@reference '../styles/global.css';

@layer components {
  .sidebar {
    @apply sticky top-0 flex h-screen w-[232px] shrink-0 flex-col border-r border-line bg-panel;
    @apply px-5 pt-9 pb-5;

    @variant max-[1250px] {
      @apply w-[216px] px-[15px];
    }

    @variant max-[1020px] {
      @apply w-[200px] px-2.5;
    }

    @variant max-[760px] {
      @apply z-20 h-[75px] w-full flex-row items-center justify-between gap-[18px];
      @apply border-r-0 border-b px-[18px] py-0;
    }

    @variant max-[440px] {
      @apply gap-2 px-[15px];
    }
  }

  .brand {
    @apply flex items-center gap-[11px] px-[11px] text-2xl leading-[1.2] font-extrabold;
    @apply tracking-[-0.8px];

    @variant max-[1020px] {
      @apply gap-2 text-[21px];
    }

    @variant max-[760px] {
      @apply px-0;
    }

    @variant max-[440px] {
      @apply text-[19px];
    }
  }

  .brand-icon {
    @apply grid size-[42px] shrink-0 place-items-center rounded-xl bg-accent text-white;

    @variant max-[760px] {
      @apply size-[34px] rounded-[10px];
    }
  }

  .primary-nav {
    @apply mt-10 grid gap-2;

    @variant max-[760px] {
      @apply mt-0 flex gap-[3px];
    }
  }

  .nav-link {
    @apply flex items-center gap-3 rounded-lg px-[15px] py-[13px] text-body font-medium;
    @apply text-[#727987] transition-[background,color] duration-150 ease-[ease] hover:bg-subtle;

    @variant max-[760px] {
      @apply gap-[7px] p-2.5 text-meta;
    }

    @variant max-[440px] {
      @apply flex-col gap-1 px-1.5 py-2;
    }
  }

  .nav-link.active {
    @apply bg-accent-soft font-semibold text-accent hover:bg-accent-soft;
  }

  .nav-count {
    @apply ml-auto grid h-[19px] min-w-5 place-items-center rounded-[5px] bg-accent-soft text-meta;
    @apply text-accent;

    @variant max-[760px] {
      @apply hidden;
    }
  }

  .topbar {
    @apply flex h-[70px] items-center justify-between border-b border-line bg-panel px-10;

    @variant max-[1250px] {
      @apply px-[30px];
    }

    @variant max-[760px] {
      @apply h-[53px] px-5;
    }
  }

  .main-content {
    @apply mx-auto w-full max-w-[1460px] flex-1 px-10 pt-[38px] pb-10;

    @variant max-[1250px] {
      @apply p-[30px];
    }

    @variant max-[1020px] {
      @apply px-6 py-7;
    }

    @variant max-[760px] {
      @apply px-5 pt-[26px] pb-[30px];
    }
  }
}
</style>
