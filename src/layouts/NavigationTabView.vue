<script setup lang="ts">
import {
  inject,
  onActivated,
  onDeactivated,
  onScopeDispose,
  provide,
  shallowReactive,
  useTemplateRef,
  watch,
} from 'vue'
import { RouterView, routeLocationKey, useRouter } from 'vue-router'

import { viewTransitionActive } from '@/shared/utils/view-transition'
import { scrollRestorationKey } from '@/shared/navigation/scroll-restoration'
import { pageScrollPosition, pageScrollTargetKey } from '@/shared/navigation/page-scroll'
import type { RouteLocationNormalizedLoaded } from 'vue-router'
import type { ScrollPosition } from '@/shared/navigation/scroll-restoration'

const props = defineProps<{ route: RouteLocationNormalizedLoaded; warning: string }>()
const router = useRouter()
const restoration = inject(scrollRestorationKey, null)
const workspace = useTemplateRef<HTMLElement>('workspace')
// Cached tabs must not observe another tab's route through useRoute().
const localRoute = shallowReactive({ ...props.route })
provide(routeLocationKey, localRoute)
provide(pageScrollTargetKey, () => workspace.value)
watch(
  () => props.route,
  (value) => Object.assign(localRoute, value),
  { flush: 'sync' },
)

let active = false
let lastPath: string | undefined
let position: ScrollPosition = { left: 0, top: 0 }

function savePosition() {
  if (active && workspace.value) {
    position = pageScrollPosition(workspace.value)
  }
}

function pageEntered(element: Element) {
  const path = element.getAttribute('data-route-key')
  if (active && path) {
    restoration?.pageEntered(path)
  }
}

// Capture before navigation can detach this tab or replace its current page.
const stopGuard = router.beforeEach(savePosition)
onScopeDispose(stopGuard)

onActivated(() => {
  active = true
  const retained = lastPath === localRoute.fullPath
  if (retained) {
    workspace.value?.scrollTo({ ...position, behavior: 'instant' })
  }

  // If history changed this hidden tab's route, its previous page must finish leaving first.
  if (lastPath === undefined || retained) {
    restoration?.pageEntered(localRoute.fullPath, retained ? position : undefined)
  }
})

onDeactivated(() => {
  active = false
  lastPath = localRoute.fullPath
})
</script>

<template>
  <div
    id="workspace-scroll"
    ref="workspace"
    class="workspace"
    tabindex="0"
    role="region"
    aria-label="页面内容"
    @scroll="savePosition"
  >
    <div
      v-if="warning"
      class="mobile-connection-warning"
      role="alert"
    >
      <span
        class="status-dot offline"
        aria-hidden="true"
      />
      {{ warning }}
    </div>
    <main
      id="main-content"
      class="main-content"
    >
      <RouterView
        v-slot="{ Component, route: currentRoute }"
        :route="localRoute"
      >
        <Transition
          name="page"
          :mode="viewTransitionActive ? undefined : 'out-in'"
          :css="!viewTransitionActive"
          @enter="pageEntered"
        >
          <KeepAlive
            include="ProgrammeLibraryView"
            :max="1"
          >
            <component
              :is="Component"
              :key="currentRoute.path"
              :data-route-key="currentRoute.fullPath"
              class="page-view"
            />
          </KeepAlive>
        </Transition>
      </RouterView>
    </main>
  </div>
</template>

<style scoped>
.workspace {
  display: flex;
  min-width: 0;
  min-height: 0;
  flex: 1;
  flex-direction: column;
  overflow: auto;
  overscroll-behavior-y: contain;
  scrollbar-gutter: stable;
}
.workspace:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: -2px;
}
.mobile-connection-warning {
  display: none;
}
.main-content {
  container: workspace / inline-size;
  width: 100%;
  max-width: 1440px;
  flex: 1;
  margin: 0 auto;
  padding: clamp(26px, 2.8vw, 44px) var(--page-gutter) 48px;
}
@media (width < 760px) {
  .mobile-connection-warning {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 38px;
    padding: 8px 16px;
    background: var(--subtle);
    color: var(--muted);
    font-size: 12px;
  }
  .main-content {
    padding: 22px 16px 32px;
  }
}
</style>
