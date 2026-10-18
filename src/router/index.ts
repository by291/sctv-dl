import { createRouter, createWebHistory, createWebHashHistory } from 'vue-router'

import { createScrollRestoration } from '@/shared/navigation/scroll-restoration'
import { pageScrollPosition } from '@/shared/navigation/page-scroll'
import type { ScrollPosition, ScrollRestoration } from '@/shared/navigation/scroll-restoration'

export function createAppRouter(
  kind: 'web' | 'tauri',
  restoration: ScrollRestoration = createScrollRestoration(),
) {
  const history = kind === 'tauri' ? createWebHashHistory() : createWebHistory()
  const entryPositions = new Map<number, ScrollPosition>()
  let currentEntry = history.state.position

  const router = createRouter({
    history,
    routes: [
      {
        path: '/',
        name: 'library',
        component: () => import('@/features/programmes/views/ProgrammeLibraryView.vue'),
        meta: { title: '节目库' },
      },
      {
        path: '/programmes/:id',
        name: 'programme',
        component: () => import('@/features/programmes/views/ProgrammeArchiveView.vue'),
        props: true,
        meta: { title: '节目详情' },
      },
      {
        path: '/history',
        name: 'history',
        component: () => import('@/features/history/views/ViewingHistoryView.vue'),
        meta: { title: '观看历史' },
      },
      {
        path: '/settings',
        name: 'settings',
        component: () => import('@/features/settings/views/SettingsView.vue'),
        meta: { title: '设置' },
      },
      ...(kind === 'tauri'
        ? [
            {
              path: '/downloads',
              name: 'downloads',
              component: () => import('@/features/downloads/views/DownloadTasksView.vue'),
              meta: { title: '下载任务' },
            },
          ]
        : []),
      { path: '/:pathMatch(.*)*', redirect: '/' },
    ],
    // The cached library restores its position after its DOM has been reactivated.
    scrollBehavior: (to, from, savedPosition) => {
      // Vue Router also invokes this for a click on the already-active navigation link.
      if (to.fullPath === from.fullPath && !savedPosition) {
        return false
      }

      // Vue Router records window offsets. Back/forward entries need the workspace offset.
      const position = savedPosition
        ? (entryPositions.get(Number(history.state.position)) ?? savedPosition)
        : null
      if (to.name === 'programme') {
        const freshEntry = !savedPosition && from.matched.length > 0
        const target = freshEntry ? { left: 0, top: 0 } : position
        // A new visit starts at the heading. Keep the explicit zero through async hydration;
        // persisted browse offsets are only a fallback for an initial document load.
        restoration.captureSavedPosition(to.fullPath, target)
        if (target) {
          restoration.scrollOnEnter(to.fullPath, target, savedPosition ? 'history' : 'navigation')
        }

        return false
      }

      if (to.name !== 'library') {
        restoration.scrollOnEnter(
          to.fullPath,
          position ?? { left: 0, top: 0 },
          savedPosition ? 'history' : 'navigation',
        )
      }

      return false
    },
  })
  router.beforeEach(() => {
    if (typeof currentEntry === 'number') {
      entryPositions.set(currentEntry, pageScrollPosition())
    }

    restoration.cancel()
  })
  router.afterEach((to) => {
    currentEntry = history.state.position
    document.title = `${String(to.meta.title || '节目库')} · sctv-dl`
  })

  return router
}
