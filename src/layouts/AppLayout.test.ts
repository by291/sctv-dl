// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider, NSelect } from 'naive-ui'

import AppLayout from './AppLayout.vue'
import LibraryView from '../features/programmes/views/LibraryView.vue'
import ProgrammeView from '../features/programmes/views/ProgrammeView.vue'
import SettingsView from '../features/settings/views/SettingsView.vue'
import { api } from '../features/programmes/api'
import { useProgrammeStore } from '../features/programmes/store'
import { useSettingsStore } from '../features/settings/store'

import type { VueWrapper } from '@vue/test-utils'

vi.mock('../features/programmes/api', () => ({
  api: { dates: vi.fn(), contents: vi.fn(), programmes: vi.fn() },
}))

let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>

beforeEach(async () => {
  localStorage.clear()
  vi.mocked(api.dates).mockResolvedValue([])
  const pinia = createPinia()
  setActivePinia(pinia)
  const catalogue = useProgrammeStore()
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
      { path: '/', name: 'library', component: LibraryView },
      { path: '/programmes/:id', component: ProgrammeView, props: true },
      { path: '/settings', component: SettingsView },
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
  useProgrammeStore().$dispose()
  useSettingsStore().$dispose()
  vi.restoreAllMocks()
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
    const scroll = vi.spyOn(window, 'scrollTo')
    window.scrollTo({ top: 640, left: 0 })
    await router.push('/programmes/1')
    await flushPromises()
    window.scrollTo({ top: 0, left: 0 })
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
    vi.mocked(api.dates).mockImplementation((_id, signal) => {
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
