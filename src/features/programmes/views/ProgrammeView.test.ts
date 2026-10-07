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

import type { VueWrapper } from '@vue/test-utils'

vi.mock('../api', () => ({
  api: { dates: vi.fn(), contents: vi.fn(), programmes: vi.fn() },
}))

let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>
let saves: { url: string; filename: string }[]

function videoResponse() {
  return new Response(null, {
    headers: {
      'content-type': 'video/mp4',
      'content-disposition': 'attachment; filename="programme.mp4"',
    },
  })
}

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
  saves = []
  vi.stubGlobal(
    'fetch',
    vi.fn().mockImplementation(async () => videoResponse()),
  )
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (
    this: HTMLAnchorElement,
  ) {
    saves.push({ url: this.href, filename: this.download })
  })
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
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('programme download choices', () => {
  it('hands a single programme to the browser as soon as a quality is selected', async () => {
    await wrapper.find(`[aria-label="下载${both.title}"]`).trigger('click')
    await flushPromises()
    expect(saves).toEqual([])
    expect(wrapper.findAll('[role="menuitem"]')).toHaveLength(2)
    await wrapper
      .findAll('[role="menuitem"]')
      .find((option) => option.text() === '流畅')!
      .trigger('click')
    await flushPromises()

    expect(saves).toHaveLength(1)
    const url = new URL(saves[0]!.url)
    expect(url.searchParams.get('url')).toBe(both.smoothVideo)
    expect(url.searchParams.get('download')).toBe('1')
    expect(saves[0]!.filename).toBe('2026-10-06_Programme（2026.10.06）_流畅.mp4')
    expect(router.currentRoute.value.path).toBe('/programmes/1')
    expect(wrapper.find('.n-message').text()).toContain('已交给浏览器')
    expect(localStorage.getItem('sctv-dl:downloads')).toBeNull()
  })

  it('downloads selected items directly and reports batch quality fallbacks', async () => {
    await wrapper.find('.selection-toolbar [role="checkbox"]').trigger('click')
    await wrapper.find('.content-toolbar button').trigger('click')
    await flushPromises()
    expect(saves).toEqual([])
    expect(wrapper.findAll('[role="menuitem"]')).toHaveLength(2)
    await wrapper
      .findAll('[role="menuitem"]')
      .find((option) => option.text() === '流畅')!
      .trigger('click')
    await flushPromises()

    expect(saves.map((save) => new URL(save.url).searchParams.get('url'))).toEqual([
      both.smoothVideo,
      standardOnly.video,
    ])
    expect(wrapper.find('.n-message').text()).toContain('2 个视频')
    expect(wrapper.find('.n-message').text()).toContain('使用标准画质')
    expect(router.currentRoute.value.path).toBe('/programmes/1')
  })

  it('disables a missing variant and never downloads when the menu is dismissed', async () => {
    useSettingsStore().quality = 'smooth'
    await wrapper.find('[aria-label="下载Clip"]').trigger('click')
    await flushPromises()
    const options = wrapper.findAll('[role="menuitem"]')
    expect(options).toHaveLength(2)
    const smooth = options.find((option) => option.text() === '流畅')!
    expect(smooth.attributes('aria-disabled')).toBe('true')
    await smooth.trigger('click')
    expect(saves).toEqual([])
    await wrapper.find('[aria-label="下载Clip"]').trigger('click')
    await flushPromises()
    expect(saves).toEqual([])
    expect(fetch).not.toHaveBeenCalled()
  })

  it('reports a failed download and allows retrying from the same row', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response(null, { status: 403 }))
    await chooseSingleQuality('标准')

    expect(saves).toEqual([])
    expect(wrapper.find('.n-message').text()).toContain('HTTP 403')
    await chooseSingleQuality('标准')
    expect(saves).toHaveLength(1)
  })

  it('continues a batch after one video fails and identifies the failed video', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response(null, { status: 403 }))
    await wrapper.find('.selection-toolbar [role="checkbox"]').trigger('click')
    await wrapper.find('.content-toolbar button').trigger('click')
    await flushPromises()
    await wrapper
      .findAll('[role="menuitem"]')
      .find((option) => option.text() === '标准')!
      .trigger('click')
    await flushPromises()

    expect(saves).toHaveLength(1)
    expect(saves[0]!.filename).toBe('2026-10-06_Clip_标准.mp4')
    expect(wrapper.find('.n-message').text()).toContain('1 个视频已交给浏览器')
    expect(wrapper.find('.n-message').text()).toContain(both.title)
    expect(wrapper.find('.n-message').text()).toContain('HTTP 403')
  })

  it('prevents repeated download clicks during preparation and permits another download afterward', async () => {
    let finish!: (response: Response) => void
    vi.mocked(fetch).mockReturnValueOnce(
      new Promise((resolve) => {
        finish = resolve
      }),
    )
    await chooseSingleQuality('标准')
    const button = wrapper.find(`[aria-label="下载${both.title}"]`)
    expect(button.attributes('disabled')).toBeDefined()
    await button.trigger('click')
    expect(fetch).toHaveBeenCalledTimes(1)

    finish(videoResponse())
    await flushPromises()
    expect(button.attributes('disabled')).toBeUndefined()
    await chooseSingleQuality('标准')
    expect(saves).toHaveLength(2)
  })
})

async function chooseSingleQuality(quality: string) {
  await wrapper.find(`[aria-label="下载${both.title}"]`).trigger('click')
  await flushPromises()
  await wrapper
    .findAll('[role="menuitem"]')
    .find((option) => option.text() === quality)!
    .trigger('click')
  await flushPromises()
}
