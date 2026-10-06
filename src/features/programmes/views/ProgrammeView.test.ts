// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider } from 'naive-ui'

import ProgrammeView from './ProgrammeView.vue'
import { api } from '../api'
import { useProgrammeStore } from '../store'
import { useSettingsStore } from '../../settings/store'
import { useDownloadStore } from '../../downloads/store'

import type { VueWrapper } from '@vue/test-utils'

vi.mock('../api', () => ({
  api: { dates: vi.fn(), contents: vi.fn(), programmes: vi.fn() },
}))

let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>
const both = {
  id: '11',
  title: 'Programme（2026.10.06）',
  cover: null,
  publishedAt: null,
  video: 'https://fscgc.scgchc.com/full.mp4',
  smoothVideo: 'https://fscgc.scgchc.com/smooth.mp4',
}
const standardOnly = { ...both, id: '12', title: 'Clip', smoothVideo: null }

beforeEach(async () => {
  localStorage.clear()
  const pinia = createPinia()
  setActivePinia(pinia)
  useProgrammeStore().programmes = [{ id: '1', name: 'Programme', cover: null }]
  vi.mocked(api.dates).mockResolvedValue([{ id: '100', date: '2026-10-06' }])
  vi.mocked(api.contents).mockResolvedValue([both, standardOnly])
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: () => import('./LibraryView.vue') },
      { path: '/programmes/:id', component: ProgrammeView, props: true },
      { path: '/downloads', component: () => import('../../downloads/views/DownloadsView.vue') },
    ],
  })
  await router.push('/programmes/1')
  await router.isReady()
  wrapper = mount(
    {
      components: { NMessageProvider, ProgrammeView },
      template: '<NMessageProvider><ProgrammeView id="1" /></NMessageProvider>',
    },
    { global: { plugins: [pinia, router], stubs: { teleport: true } } },
  )
  await flushPromises()
})

afterEach(() => {
  wrapper.unmount()
  useProgrammeStore().$dispose()
  useSettingsStore().$dispose()
  useDownloadStore().$dispose()
})

describe('programme download choices', () => {
  it('queues a single programme immediately after a menu quality is selected', async () => {
    await wrapper.find(`[aria-label="下载${both.title}"]`).trigger('click')
    await flushPromises()
    expect(useDownloadStore().tasks).toEqual([])
    expect(wrapper.findAll('[role="menuitem"]')).toHaveLength(2)
    await wrapper
      .findAll('[role="menuitem"]')
      .find((option) => option.text() === '流畅')!
      .trigger('click')
    await flushPromises()

    expect(useDownloadStore().tasks).toMatchObject([
      { contentId: '11', quality: 'smooth', url: both.smoothVideo },
    ])
    expect(router.currentRoute.value.path).toBe('/programmes/1')
    expect(wrapper.find('.n-message').text()).toContain('已加入 1 个下载任务')
  })

  it('queues selected items with the menu quality and reports batch fallbacks in one toast', async () => {
    await wrapper.find('.selection-toolbar [role="checkbox"]').trigger('click')
    await wrapper.find('.content-toolbar button').trigger('click')
    await flushPromises()
    expect(useDownloadStore().tasks).toEqual([])
    expect(wrapper.findAll('[role="menuitem"]')).toHaveLength(2)
    await wrapper
      .findAll('[role="menuitem"]')
      .find((option) => option.text() === '流畅')!
      .trigger('click')
    await flushPromises()

    expect(useDownloadStore().tasks).toMatchObject([
      { contentId: '11', quality: 'smooth' },
      { contentId: '12', quality: 'standard' },
    ])
    expect(wrapper.findAll('.n-message')).toHaveLength(1)
    expect(wrapper.find('.n-message').text()).toContain('已加入 2 个下载任务')
    expect(wrapper.find('.n-message').text()).toContain('使用标准画质')
    expect(router.currentRoute.value.path).toBe('/programmes/1')
  })

  it('disables a missing variant regardless of preference and dismissing the menu adds no tasks', async () => {
    useSettingsStore().quality = 'smooth'
    await wrapper.find('[aria-label="下载Clip"]').trigger('click')
    await flushPromises()
    const options = wrapper.findAll('[role="menuitem"]')
    expect(options).toHaveLength(2)
    const smooth = options.find((option) => option.text() === '流畅')!
    expect(smooth.attributes('aria-disabled')).toBe('true')
    await smooth.trigger('click')
    expect(useDownloadStore().tasks).toEqual([])
    await wrapper.find('[aria-label="下载Clip"]').trigger('click')
    await flushPromises()
    expect(useDownloadStore().tasks).toEqual([])
  })
})
