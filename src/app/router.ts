import { createRouter, createWebHistory } from 'vue-router'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'library',
      component: () => import('../features/programmes/views/LibraryView.vue'),
      meta: { title: '节目库' },
    },
    {
      path: '/programmes/:id',
      name: 'programme',
      component: () => import('../features/programmes/views/ProgrammeView.vue'),
      props: true,
      meta: { title: '节目详情' },
    },
    {
      path: '/settings',
      name: 'settings',
      component: () => import('../features/settings/views/SettingsView.vue'),
      meta: { title: '设置' },
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
  // The cached library restores its position after its DOM has been reactivated.
  scrollBehavior: (to, _from, savedPosition) =>
    to.name === 'library' ? false : (savedPosition ?? { top: 0 }),
})
router.afterEach((to) => {
  document.title = `${String(to.meta.title || '节目库')} · sctv-dl`
})
