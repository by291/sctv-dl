// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider } from 'naive-ui'

import AppLayout from '@/layouts/AppLayout.vue'
import DownloadTasksView from '@/features/downloads/views/DownloadTasksView.vue'
import {
  createPlatformFixture,
  createDownloadTaskFixture,
  createNativeDownloadFixture,
} from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'

import type { AppPlatform, NativeDownloadPort } from '@/shared/platform/ports'
import type { DownloadTask, DownloadEvent } from '@shared/contracts/downloads'
import type { VueWrapper } from '@vue/test-utils'

let wrapper: VueWrapper | undefined

afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
})

async function mountShell(platform: AppPlatform) {
  const pinia = createPinia()
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'library', component: { template: '<h1>节目库</h1>' } },
      { path: '/downloads', component: DownloadTasksView },
      { path: '/settings', component: { template: '<h1>设置</h1>' } },
      { path: '/history', component: { template: '<h1>观看历史</h1>' } },
    ],
  })
  await router.push('/')
  await router.isReady()
  wrapper = mount(
    {
      components: { AppLayout, NMessageProvider },
      template: '<NMessageProvider><AppLayout /></NMessageProvider>',
    },
    {
      attachTo: document.body,
      global: { plugins: [pinia, router], provide: { [platformKey as symbol]: platform } },
    },
  )
  await flushPromises()

  return { router, tasks: useDownloadTasksStore(pinia) }
}

it('keeps native observation and the active badge alive across route changes', async () => {
  const task: DownloadTask = {
    ...createDownloadTaskFixture(),
    id: 'job',
    content: { programmeId: '1', dateId: '2', contentId: '3' },
    filename: 'news.mp4',
    quality: 'standard',
    state: 'running',
    receivedBytes: 1024,
    totalBytes: null,
    revision: 2,
    error: null,
  }
  let listener: (value: DownloadEvent) => void = () => {}

  const dispose = vi.fn()
  const cancel = vi.fn<NativeDownloadPort['cancel']>()
  const downloads: NativeDownloadPort = {
    ...createNativeDownloadFixture(),
    kind: 'native',
    subscribeEvents: async (next) => {
      listener = next

      return dispose
    },
    snapshot: async () => ({ epoch: 'one', revision: 2, tasks: [task] }),
    start: async () => ({ kind: 'cancelled' }),
    cancel,
    getDirectory: async () => null,
    chooseDirectory: async () => null,
  }
  const platform = { ...createPlatformFixture(), kind: 'tauri' as const, downloads }
  const { router, tasks } = await mountShell(platform)
  const link = wrapper!.get('nav a[href="/downloads"]')
  expect(link.text()).toContain('1')

  await link.trigger('click')
  await flushPromises()
  expect(router.currentRoute.value.path).toBe('/downloads')
  await router.push('/settings')
  await flushPromises()
  listener({
    epoch: 'one',
    revision: 3,
    kind: 'upsert',
    task: { ...task, state: 'completed', receivedBytes: 2048, revision: 3 },
  })
  await flushPromises()

  expect(tasks.tasks[0]?.state).toBe('completed')
  expect(wrapper!.get('nav a[href="/downloads"]').text()).not.toContain('1')
  expect(dispose).not.toHaveBeenCalled()
  wrapper!.unmount()
  wrapper = undefined
  expect(dispose).toHaveBeenCalledOnce()
  expect(cancel).not.toHaveBeenCalled()
})

it('keeps native download navigation out of the browser application', async () => {
  await mountShell(createPlatformFixture())

  expect(wrapper!.find('nav a[href="/downloads"]').exists()).toBe(false)
})

it('retains native task filters, selection, and position after visiting all other tabs', async () => {
  const task = { ...createDownloadTaskFixture(), state: 'completed' as const, fileAvailable: true }
  const downloads = createNativeDownloadFixture()
  downloads.snapshot = async () => ({ epoch: 'one', revision: 1, tasks: [task] })
  const { router } = await mountShell({ ...createPlatformFixture(), kind: 'tauri', downloads })
  await router.push('/downloads')
  await flushPromises()
  await wrapper!
    .findAll('.download-filter')
    .find((button) => button.text().includes('已完成'))!
    .trigger('click')
  await flushPromises()
  await wrapper!.get('[aria-label="选择任务：news.mp4"]').trigger('click')
  const workspace = wrapper!.get<HTMLElement>('#workspace-scroll').element
  workspace.scrollTo({ top: 320 })

  for (const path of ['/settings', '/history', '/']) {
    await router.push(path)
    await flushPromises()
  }

  await router.push('/downloads')
  await flushPromises()

  expect(wrapper!.get('.download-filter[aria-pressed="true"]').text()).toContain('已完成')
  expect(wrapper!.get('[aria-label="选择任务：news.mp4"]').attributes('aria-checked')).toBe('true')
  expect(wrapper!.get<HTMLElement>('#workspace-scroll').element.scrollTop).toBe(320)
})
