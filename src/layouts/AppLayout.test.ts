// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider, NSelect } from 'naive-ui'

import AppLayout from '@/layouts/AppLayout.vue'
import ProgrammeLibraryView from '@/features/programmes/views/ProgrammeLibraryView.vue'
import ProgrammeArchiveView from '@/features/programmes/views/ProgrammeArchiveView.vue'
import SettingsView from '@/features/settings/views/SettingsView.vue'
import ViewingHistoryView from '@/features/history/views/ViewingHistoryView.vue'
import type { ProgrammeApi } from '@/shared/platform/ports'
import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'

import type { VueWrapper } from '@vue/test-utils'

const programmeApi = vi.hoisted(() => ({
  dates: vi.fn<ProgrammeApi['dates']>(),
  contents: vi.fn<ProgrammeApi['contents']>(),
  programmes: vi.fn<ProgrammeApi['programmes']>(),
}))

vi.mock('@/shared/platform/usePlatform', async () => {
  const { createPlatformFixture } = await import('@/shared/platform/platform.test-support')

  return { usePlatform: () => ({ ...createPlatformFixture(), programmes: programmeApi }) }
})

let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>

beforeEach(async () => {
  localStorage.clear()
  vi.stubEnv('APP_VERSION', '9.8.7-test')
  vi.mocked(programmeApi.dates).mockResolvedValue([])
  const pinia = createPinia()
  setActivePinia(pinia)
  const catalogue = useProgrammeCatalogueStore()
  catalogue.programmes = [
    { id: '1', name: 'Bravo', cover: null },
    { id: '2', name: 'Alpha', cover: null },
    { id: '3', name: 'Charlie', cover: null },
  ]
  catalogue.updatedAt = new Date()
  useSettingsStore().favourites = ['1', '2']
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'library', component: ProgrammeLibraryView },
      { path: '/programmes/:id', component: ProgrammeArchiveView, props: true },
      { path: '/settings', component: SettingsView },
      { path: '/history', component: ViewingHistoryView },
    ],
  })
  await router.push('/')
  await router.isReady()
  wrapper = mount(
    {
      components: { NMessageProvider, AppLayout },
      template: '<NMessageProvider><AppLayout /></NMessageProvider>',
    },
    { attachTo: document.body, global: { plugins: [pinia, router] } },
  )
  await flushPromises()
})

afterEach(() => {
  wrapper.unmount()
  useProgrammeCatalogueStore().$dispose()
  useSettingsStore().$dispose()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

it('shows the build version instead of a fixed product version', () => {
  expect(wrapper.get('.version').text()).toBe('Web · v9.8.7-test')
})

it('returns to the retained programme and its scroll container when switching tabs', async () => {
  await router.push('/programmes/1')
  await flushPromises()
  const detail = wrapper.get('.detail-cover').element
  const workspace = wrapper.get<HTMLElement>('#workspace-scroll').element
  workspace.scrollTo({ top: 640 })
  await wrapper.get('#workspace-scroll').trigger('scroll')
  const calls = programmeApi.dates.mock.calls.length

  await router.push('/settings')
  await flushPromises()
  expect(wrapper.get('#workspace-scroll').element).not.toBe(workspace)
  expect(wrapper.get('.nav-link').attributes('href')).toBe('/programmes/1')
  await wrapper.get('.nav-link').trigger('click')
  await flushPromises()

  expect(router.currentRoute.value.path).toBe('/programmes/1')
  expect(wrapper.get('.detail-cover').element).toBe(detail)
  expect(wrapper.get<HTMLElement>('#workspace-scroll').element.scrollTop).toBe(640)
  expect(programmeApi.dates.mock.calls.length).toBe(calls)

  await wrapper.get('.back-link').trigger('click')
  await flushPromises()
  expect(wrapper.find('.library-view').exists()).toBe(true)
  expect(wrapper.get('.nav-link').attributes('href')).toBe('/')
})

it('retains the history search and independent scroll position while other tabs are active', async () => {
  await router.push('/history')
  await flushPromises()
  await wrapper.get('input[placeholder="搜索节目、栏目或日期"]').setValue('Bravo')
  const workspace = wrapper.get<HTMLElement>('#workspace-scroll').element
  workspace.scrollTo({ top: 280 })
  await wrapper.get('#workspace-scroll').trigger('scroll')

  await router.push('/settings')
  await flushPromises()
  await router.push('/history')
  await flushPromises()

  expect(wrapper.get<HTMLInputElement>('input').element.value).toBe('Bravo')
  expect(wrapper.get<HTMLElement>('#workspace-scroll').element.scrollTop).toBe(280)
})

it('keeps an archive request alive across tabs without moving the visible tab when it finishes', async () => {
  let finish!: (dates: Awaited<ReturnType<ProgrammeApi['dates']>>) => void
  let signal: AbortSignal | undefined
  programmeApi.dates.mockImplementation((_id, requestSignal) => {
    signal = requestSignal

    return new Promise((resolve) => {
      finish = resolve
    })
  })
  programmeApi.contents.mockResolvedValue([])
  await router.push('/programmes/1')
  await flushPromises()
  const detail = wrapper.get('.detail-cover').element

  await router.push('/settings')
  await flushPromises()
  const settings = wrapper.get<HTMLElement>('#workspace-scroll').element
  settings.scrollTo({ top: 120 })
  finish([{ id: '10', date: '2026-10-18' }])
  await flushPromises()
  expect(signal?.aborted).toBe(false)
  expect(settings.scrollTop).toBe(120)
  expect(wrapper.get('h1').text()).toBe('设置')

  await wrapper.get('.nav-link').trigger('click')
  await flushPromises()
  expect(wrapper.get('.detail-cover').element).toBe(detail)
  expect(programmeApi.contents).toHaveBeenCalledWith('1', '10', expect.any(AbortSignal))
  expect(wrapper.text()).toContain('2026-10-18')
})

it('restores the retained tab through browser back and forward navigation', async () => {
  await router.push('/programmes/1')
  await flushPromises()
  const detail = wrapper.get('.detail-cover').element
  const workspace = wrapper.get<HTMLElement>('#workspace-scroll').element
  workspace.scrollTo({ top: 500 })
  await router.push('/settings')
  await flushPromises()

  router.back()
  await flushPromises()
  expect(wrapper.get('.detail-cover').element).toBe(detail)
  expect(wrapper.get<HTMLElement>('#workspace-scroll').element.scrollTop).toBe(500)
  router.forward()
  await flushPromises()
  expect(wrapper.get('h1').text()).toBe('设置')
})

it('keeps connection announcements available across navigation and recovery', async () => {
  const catalogue = useProgrammeCatalogueStore()
  expect(wrapper.get('[role="status"]').text()).toBe('已连接节目服务')

  catalogue.error = 'The programme service is unavailable.'
  await router.push('/settings')
  await flushPromises()

  expect(wrapper.get('[role="status"]').text()).toBe('连接暂时不可用')
  expect(wrapper.get('[role="alert"]').text()).toBe('连接暂时不可用')

  catalogue.error = ''
  await wrapper.vm.$nextTick()

  expect(wrapper.get('[role="status"]').text()).toBe('已连接节目服务')
  expect(wrapper.find('[role="alert"]').exists()).toBe(false)
})

describe('library return navigation', () => {
  it.each(['link', 'history', 'settings'])(
    'restores the same library instance via %s',
    async (entry) => {
      const originalCover = wrapper.get('.featured-image').element
      const featured = wrapper.get('.featured-title').text()
      await wrapper.get('input').setValue('a')
      await wrapper.findAll('[role="tab"]')[1]!.trigger('click')
      wrapper.findComponent(NSelect).vm.$emit('update:value', 'name')
      await flushPromises()
      expect(wrapper.findAll('.programme-name').map((name) => name.text())).toEqual([
        'Alpha',
        'Bravo',
      ])

      await router.push(entry === 'settings' ? '/settings' : '/programmes/1')
      await flushPromises()

      if (entry === 'history') {
        router.back()
      } else if (entry === 'settings') {
        await wrapper.get('.nav-link').trigger('click')
      } else {
        await wrapper.get('.back-link').trigger('click')
      }

      await flushPromises()
      expect(wrapper.get('.featured-image').element === originalCover).toBe(true)
      expect(wrapper.get('.featured-title').text()).toBe(featured)
      expect(wrapper.get('input').element.value).toBe('a')
      expect(wrapper.findAll('[role="tab"]')[1]!.attributes('aria-selected')).toBe('true')
      expect(wrapper.findComponent(NSelect).props('value')).toBe('name')
      expect(wrapper.findAll('.programme-name').map((name) => name.text())).toEqual([
        'Alpha',
        'Bravo',
      ])
    },
  )

  it('restores the library scroll position after it is reactivated', async () => {
    const workspace = wrapper.get<HTMLElement>('#workspace-scroll').element
    const scroll = vi.spyOn(workspace, 'scrollTo')
    workspace.scrollTo({ top: 640, left: 0 })
    await router.push('/programmes/1')
    await flushPromises()
    workspace.scrollTo({ top: 0, left: 0 })
    scroll.mockClear()
    await wrapper.get('.back-link').trigger('click')
    await flushPromises()

    expect(scroll).toHaveBeenLastCalledWith({ top: 640, left: 0, behavior: 'instant' })
  })

  it('preserves catalogue positions when favourites change in programme details', async () => {
    const originalCover = wrapper.get('.programme-cover').element
    await router.push('/programmes/1')
    await flushPromises()
    await wrapper.get('.detail-favourite').trigger('click')
    await wrapper.get('.back-link').trigger('click')
    await flushPromises()

    expect(wrapper.findAll('.programme-name').map((name) => name.text())).toEqual([
      'Bravo',
      'Alpha',
      'Charlie',
    ])
    expect(wrapper.get('.programme-cover').element).toBe(originalCover)
    expect(wrapper.get('[aria-label="收藏Bravo"]').attributes('aria-pressed')).toBe('false')
  })

  it('still unmounts programme details and aborts their pending archive request', async () => {
    let requestSignal: AbortSignal | undefined
    vi.mocked(programmeApi.dates).mockImplementation((_id, signal) => {
      requestSignal = signal

      return new Promise(() => {})
    })
    await router.push('/programmes/1')
    await flushPromises()
    const detail = wrapper.get('.detail-cover').element
    await wrapper.get('.back-link').trigger('click')
    await flushPromises()

    expect(requestSignal?.aborted).toBe(true)
    await router.push('/programmes/1')
    await flushPromises()
    expect(wrapper.get('.detail-cover').element === detail).toBe(false)
  })
})
