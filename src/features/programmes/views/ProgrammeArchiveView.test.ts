// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider } from 'naive-ui'

import { usePlatform } from '@/shared/platform/usePlatform'
import {
  createScrollRestoration,
  scrollRestorationKey,
} from '@/shared/navigation/scroll-restoration'
import ProgrammeUpdateNotice from '@/features/programmes/components/ProgrammeUpdateNotice.vue'
import ProgrammeArchiveView from '@/features/programmes/views/ProgrammeArchiveView.vue'
import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import ProgrammeContentList from '@/features/programmes/components/ProgrammeContentList.vue'
import ProgrammeDatePicker from '@/features/programmes/components/ProgrammeDatePicker.vue'
import type { ProgrammeApi } from '@/shared/platform/ports'
import type { PreparedDownload } from '@shared/contracts/downloads'
import type { BrowseStateRead } from '@shared/contracts/programme-cache'
import { downloadRequestSchema } from '@shared/contracts/downloads'
import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'

import type { VueWrapper } from '@vue/test-utils'

const programmeApi = vi.hoisted(() => ({
  dates: vi.fn<ProgrammeApi['dates']>(),
  contents: vi.fn<ProgrammeApi['contents']>(),
  programmes: vi.fn<ProgrammeApi['programmes']>(),
}))

vi.mock('@/shared/platform/usePlatform', async () => {
  const { createWebDownloads } = await import('@/features/programmes/api/downloads.web')

  const { createPlatformFixture } = await import('@/shared/platform/platform.test-support')
  const fixture = createPlatformFixture()

  return {
    usePlatform: () => ({ ...fixture, programmes: programmeApi, downloads: createWebDownloads() }),
  }
})

let pinia: ReturnType<typeof createPinia>
let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>
let saves: { url: string; filename: string }[]
const mediaFetch = vi.fn<typeof fetch>()

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
  usePlatform().programmeCache.readBrowseState = vi
    .fn()
    .mockResolvedValue({ epoch: 'fixture', value: null, persisted: true, warning: null })
  usePlatform().programmeCache.subscribeCleared = async () => () => {}

  usePlatform().programmeCache.writeBrowseState = vi
    .fn()
    .mockResolvedValue({ accepted: true, persisted: true })
  saves = []
  mediaFetch.mockReset().mockImplementation(async () => videoResponse())
  const preparedFiles: Record<string, PreparedDownload> = {
    '11:standard': {
      contentId: '11',
      title: both.title,
      url: both.video,
      filename: '2026-10-06_Programme（2026.10.06）_标准.mp4',
      quality: 'standard',
    },
    '11:smooth': {
      contentId: '11',
      title: both.title,
      url: both.smoothVideo,
      filename: '2026-10-06_Programme（2026.10.06）_流畅.mp4',
      quality: 'smooth',
    },
    '12:standard': {
      contentId: '12',
      title: 'Clip',
      url: standardOnly.video,
      filename: '2026-10-06_Clip_标准.mp4',
      quality: 'standard',
    },
    '12:smooth': {
      contentId: '12',
      title: 'Clip',
      url: standardOnly.video,
      filename: '2026-10-06_Clip_标准.mp4',
      quality: 'standard',
    },
  }
  vi.stubGlobal(
    'fetch',
    vi.fn<typeof fetch>(async (input, init) => {
      if (init?.method === 'POST' && typeof init.body === 'string') {
        const request = downloadRequestSchema.parse(JSON.parse(init.body))
        const files = request.contentIds.map((id) => preparedFiles[`${id}:${request.quality}`]!)

        return Response.json({
          data: {
            files,
            failures: [],
            usedFallback: files.some((file) => file.quality !== request.quality),
          },
        })
      }

      return mediaFetch(input, init)
    }),
  )
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (
    this: HTMLAnchorElement,
  ) {
    saves.push({ url: this.href, filename: this.download })
  })
  pinia = createPinia()
  setActivePinia(pinia)
  useProgrammeCatalogueStore().programmes = [{ id: '1', name: 'Programme', cover: null }]
  vi.mocked(programmeApi.dates).mockResolvedValue([{ id: '100', date: '2026-10-06' }])
  vi.mocked(programmeApi.contents).mockResolvedValue([both, standardOnly])
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/',
        component: () => import('@/features/programmes/views/ProgrammeLibraryView.vue'),
      },
      { path: '/programmes/:id', component: ProgrammeArchiveView, props: true },
    ],
  })
  await router.push('/programmes/1')
  await router.isReady()
  wrapper = mount(
    {
      components: { NMessageProvider, ProgrammeArchiveView },
      template: '<NMessageProvider><RouterView /></NMessageProvider>',
    },
    {
      global: { plugins: [pinia, router], stubs: { teleport: true, ProgrammePreviewDialog: true } },
    },
  )
  await flushPromises()
})

afterEach(() => {
  wrapper.unmount()
  useProgrammeCatalogueStore().$dispose()
  useSettingsStore().$dispose()
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('programme download choices', () => {
  it('switches publication order while keeping full episodes first and selected IDs intact', async () => {
    const early = {
      ...standardOnly,
      id: '13',
      title: 'Earlier clip',
      publishedAt: '2026-10-06 18:41:00',
    }
    const late = {
      ...standardOnly,
      id: '14',
      title: 'Later clip',
      publishedAt: '2026-10-06 18:55:00',
    }
    vi.mocked(programmeApi.contents).mockResolvedValue([late, both, early])
    wrapper.findComponent(ProgrammeDatePicker).vm.$emit('refresh')
    await flushPromises()

    await wrapper.get('.programme-update-apply').trigger('click')
    await flushPromises()

    const titles = () => wrapper.findAll('.content-title').map((row) => row.text())
    expect(titles()).toEqual([both.title, early.title, late.title])
    await wrapper.findAll('.content-row')[1]!.get('[role="checkbox"]').trigger('click')
    await wrapper.get('.content-sort').trigger('click')
    await flushPromises()

    expect(titles()).toEqual([both.title, late.title, early.title])
    expect(
      wrapper.findAll('.content-row')[2]!.get('[role="checkbox"]').attributes('aria-checked'),
    ).toBe('true')
    expect(wrapper.get('.selection-summary').text()).toContain('1')
    expect(wrapper.get('.content-sort').attributes('aria-label')).toContain('时间降序')
    expect(wrapper.findAll('.content-row time').map((time) => time.text())).toEqual([
      '2026-10-06 18:55:00',
      '2026-10-06 18:41:00',
    ])
    expect(wrapper.findAll('.content-row')[0]!.find('time').exists()).toBe(false)
    await wrapper.get('.content-sort').trigger('click')
    expect(titles()).toEqual([both.title, early.title, late.title])
    expect(wrapper.get('.content-sort').attributes('aria-label')).toContain('时间升序')
  })

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
    await wrapper.get('[aria-label="批量下载"]').trigger('click')
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
    mediaFetch.mockResolvedValueOnce(new Response(null, { status: 403 }))
    await chooseSingleQuality('标准')

    expect(saves).toEqual([])
    expect(wrapper.find('.n-message').text()).toContain('HTTP 403')
    await chooseSingleQuality('标准')
    expect(saves).toHaveLength(1)
  })

  it('continues a batch after one video fails and identifies the failed video', async () => {
    mediaFetch.mockResolvedValueOnce(new Response(null, { status: 403 }))
    await wrapper.find('.selection-toolbar [role="checkbox"]').trigger('click')
    await wrapper.get('[aria-label="批量下载"]').trigger('click')
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
    mediaFetch.mockReturnValueOnce(
      new Promise((resolve) => {
        finish = resolve
      }),
    )
    await chooseSingleQuality('标准')
    const button = wrapper.find(`[aria-label="下载${both.title}"]`)
    expect(button.attributes('disabled')).toBeDefined()
    await button.trigger('click')
    expect(mediaFetch).toHaveBeenCalledTimes(1)

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

it('pins history metadata when a preview opens and retains it while archive state changes', async () => {
  wrapper.findComponent(ProgrammeContentList).vm.$emit('preview', both)
  await flushPromises()
  const dialog = wrapper.findComponent(ProgrammePreviewDialog)
  const expected = {
    kind: 'online',
    content: both,
    metadata: {
      content: { programmeId: '1', dateId: '100', contentId: '11' },
      programmeName: 'Programme',
      broadcastDate: '2026-10-06',
      title: both.title,
      cover: null,
    },
  }
  expect(dialog.props('input')).toEqual(expected)
  useProgrammeCatalogueStore().programmes = [{ id: '1', name: 'Renamed programme', cover: null }]
  wrapper.findComponent(ProgrammeDatePicker).vm.$emit('update:modelValue', '2026-10-05')
  await flushPromises()
  expect(dialog.props('input')).toEqual(expected)
  expect(dialog.props('reference')).toEqual(expected.metadata.content)
})

it('does not open an unidentifiable preview while the broadcast date is unavailable', async () => {
  const list = wrapper.findComponent(ProgrammeContentList)
  wrapper.findComponent(ProgrammeDatePicker).vm.$emit('update:modelValue', null)
  list.vm.$emit('preview', both)
  await flushPromises()
  expect(wrapper.findComponent(ProgrammePreviewDialog).props('input')).toBeNull()
})

it('keeps preview metadata and batch selection stable while an update is waiting', async () => {
  wrapper.findComponent(ProgrammeContentList).vm.$emit('preview', both)
  await wrapper.find('.selection-toolbar [role="checkbox"]').trigger('click')
  programmeApi.contents.mockResolvedValueOnce([{ ...both, title: 'Changed title' }])
  wrapper.findComponent(ProgrammeDatePicker).vm.$emit('refresh')
  await flushPromises()
  const notice = wrapper.findComponent(ProgrammeUpdateNotice)
  expect(notice.props('pending')).toBe(true)
  expect(notice.props('held')).toBe(true)
  expect(wrapper.findComponent(ProgrammePreviewDialog).props('modelValue')?.title).toBe(both.title)
  expect(wrapper.get('.selection-summary').text()).toContain('2')
  notice.vm.$emit('accept')
  await flushPromises()
  expect(wrapper.findAll('.content-title').map((row) => row.text())).toContain(both.title)
})

it('restores the saved date and descending sort before content rendering, with browser scroll precedence', async () => {
  wrapper.unmount()
  programmeApi.contents.mockClear().mockResolvedValue([
    { ...both, id: '21', title: 'Early clip', publishedAt: '2026-10-05 10:00:00' },
    { ...both, id: '22', title: 'Late clip', publishedAt: '2026-10-05 11:00:00' },
  ])
  programmeApi.dates.mockResolvedValue([
    { id: '100', date: '2026-10-06' },
    { id: '99', date: '2026-10-05' },
  ])
  const savedState: BrowseStateRead = {
    epoch: 'fixture',
    value: {
      programmeId: '1',
      dateId: '99',
      date: '2026-10-05',
      sort: 'desc',
      scrollY: 700,
      visitedAt: '2026-10-17T00:00:00Z',
    },
    persisted: true,
    warning: null,
  }
  let resolveRead!: () => void
  usePlatform().programmeCache.readBrowseState = vi.fn(
    () =>
      new Promise<BrowseStateRead>((resolve) => {
        resolveRead = () => resolve(savedState)
      }),
  )
  const write = vi.mocked(usePlatform().programmeCache.writeBrowseState)
  write.mockClear()
  const scroll = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  vi.spyOn(document.documentElement, 'scrollHeight', 'get').mockReturnValue(2000)
  vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(600)
  await router.push('/programmes/1')
  const cleared: Array<(epoch: string) => void> = []
  usePlatform().programmeCache.subscribeCleared = async (listener) => {
    cleared.push(listener)

    return () => {}
  }

  const restoration = createScrollRestoration()
  restoration.captureSavedPosition('/programmes/1', { left: 0, top: 400 })
  wrapper = mount(
    {
      components: { NMessageProvider, ProgrammeArchiveView },
      template: '<NMessageProvider><RouterView /></NMessageProvider>',
    },
    {
      global: {
        plugins: [pinia, router],
        provide: { [scrollRestorationKey as symbol]: restoration },
        stubs: { teleport: true, ProgrammePreviewDialog: true },
      },
    },
  )
  await flushPromises()
  expect(write).not.toHaveBeenCalled()
  resolveRead()
  await flushPromises()
  await new Promise((resolve) => requestAnimationFrame(resolve))
  expect(programmeApi.contents).toHaveBeenCalledExactlyOnceWith('1', '99', expect.any(AbortSignal))
  expect(wrapper.findAll('.content-title').map((row) => row.text())).toEqual([
    'Late clip',
    'Early clip',
  ])
  expect(scroll).toHaveBeenCalledWith({ left: 0, top: 400, behavior: 'instant' })
  for (const listener of cleared) {
    listener('cleared')
  }

  await flushPromises()
  expect(wrapper.findAll('.content-title').map((row) => row.text())).toEqual([
    'Late clip',
    'Early clip',
  ])
  expect(programmeApi.contents).toHaveBeenCalledTimes(1)
})

it('persists a changed date and sort without waiting for navigation or document hiding', async () => {
  programmeApi.dates.mockResolvedValue([
    { id: '100', date: '2026-10-06' },
    { id: '99', date: '2026-10-05' },
  ])
  wrapper.findComponent(ProgrammeDatePicker).vm.$emit('refresh')
  await flushPromises()
  wrapper.findComponent(ProgrammeUpdateNotice).vm.$emit('accept')
  await flushPromises()
  await new Promise((resolve) => requestAnimationFrame(resolve))
  const write = vi.mocked(usePlatform().programmeCache.writeBrowseState)
  write.mockClear()

  wrapper.findComponent(ProgrammeDatePicker).vm.$emit('update:modelValue', '2026-10-05')
  await flushPromises()
  expect(write).toHaveBeenLastCalledWith(
    expect.objectContaining({ programmeId: '1', dateId: '99', date: '2026-10-05', sort: 'asc' }),
    'fixture',
  )
  await wrapper.get('.content-sort').trigger('click')
  await flushPromises()
  expect(write).toHaveBeenLastCalledWith(
    expect.objectContaining({ date: '2026-10-05', sort: 'desc' }),
    'fixture',
  )
})

it('persists scroll periodically and captures the latest offset on pagehide', async () => {
  await new Promise((resolve) => requestAnimationFrame(resolve))
  const write = vi.mocked(usePlatform().programmeCache.writeBrowseState)
  write.mockClear()
  const offset = vi.spyOn(window, 'scrollY', 'get').mockReturnValue(200)
  window.dispatchEvent(new Event('scroll'))
  await flushPromises()
  expect(write).toHaveBeenLastCalledWith(expect.objectContaining({ scrollY: 200 }), 'fixture')
  const writes = write.mock.calls.length
  offset.mockReturnValue(400)
  window.dispatchEvent(new Event('scroll'))
  await flushPromises()
  expect(write).toHaveBeenCalledTimes(writes)
  window.dispatchEvent(new Event('pagehide'))
  await flushPromises()
  expect(write).toHaveBeenLastCalledWith(expect.objectContaining({ scrollY: 400 }), 'fixture')
})
