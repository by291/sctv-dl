// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NSelect } from 'naive-ui'
import { createApp } from 'vue'

import ProgrammeLibraryView from '@/features/programmes/views/ProgrammeLibraryView.vue'
import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'
import { platformKey } from '@/shared/platform/usePlatform'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'

import type { VueWrapper } from '@vue/test-utils'

let wrapper: VueWrapper
let pinia: ReturnType<typeof createPinia>
let router: ReturnType<typeof createRouter>

beforeEach(async () => {
  localStorage.clear()
  pinia = createPinia()
  const platform = createPlatformFixture()
  platform.programmes.programmes = async () => [
    { id: '3', name: 'Charlie', cover: null },
    { id: '2', name: 'Bravo', cover: null },
    { id: '1', name: 'Alpha', cover: null },
    { id: '4', name: 'Delta', cover: null },
  ]
  createApp({}).provide(platformKey, platform).use(pinia)
  setActivePinia(pinia)
  await useProgrammeCatalogueStore().load()
  useSettingsStore().favourites = ['4', '2']
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: ProgrammeLibraryView },
      {
        path: '/programmes/:id',
        component: () => import('@/features/programmes/views/ProgrammeArchiveView.vue'),
      },
    ],
  })
  await router.push('/')
  await router.isReady()
  wrapper = mount({ template: '<RouterView />' }, { global: { plugins: [pinia, router] } })
})

afterEach(() => {
  wrapper.unmount()
  useProgrammeCatalogueStore().$dispose()
  useSettingsStore().$dispose()
})

function displayedNames() {
  return wrapper.findAll('.programme-card h3').map((heading) => heading.text())
}

describe('programme catalogue ordering', () => {
  it.each([
    { sort: 'default', expected: ['Bravo', 'Delta', 'Charlie', 'Alpha'] },
    { sort: 'name', expected: ['Bravo', 'Delta', 'Alpha', 'Charlie'] },
  ])('keeps favourites first with $sort ordering inside each group', async ({ sort, expected }) => {
    wrapper.findComponent(NSelect).vm.$emit('update:value', sort)
    await wrapper.vm.$nextTick()

    expect(displayedNames()).toEqual(expected)
    expect(useProgrammeCatalogueStore().programmes.map((programme) => programme.id)).toEqual([
      '3',
      '2',
      '1',
      '4',
    ])
  })

  it.each(['default', 'name'])(
    'keeps card positions when toggling favourites in %s order',
    async (sort) => {
      wrapper.findComponent(NSelect).vm.$emit('update:value', sort)
      await wrapper.vm.$nextTick()
      const originalNames = displayedNames()

      await wrapper.find('[aria-label="收藏Charlie"]').trigger('click')
      expect(displayedNames()).toEqual(originalNames)
      expect(wrapper.get('[aria-label="取消收藏Charlie"]').attributes('aria-pressed')).toBe('true')

      await wrapper.find('[aria-label="取消收藏Bravo"]').trigger('click')
      expect(displayedNames()).toEqual(originalNames)
      expect(wrapper.get('[aria-label="收藏Bravo"]').attributes('aria-pressed')).toBe('false')
      expect(useSettingsStore().favourites).toEqual(['4', '3'])
    },
  )

  it('applies the latest favourite priority when a new browsing session starts', async () => {
    await wrapper.get('[aria-label="收藏Charlie"]').trigger('click')
    await wrapper.get('[aria-label="取消收藏Bravo"]').trigger('click')
    expect(displayedNames()).toEqual(['Bravo', 'Delta', 'Charlie', 'Alpha'])

    wrapper.unmount()
    wrapper = mount({ template: '<RouterView />' }, { global: { plugins: [pinia, router] } })
    await router.isReady()
    await wrapper.vm.$nextTick()
    expect(displayedNames()).toEqual(['Charlie', 'Delta', 'Bravo', 'Alpha'])
  })

  it('uses live favourites in their tab without resetting the all-programmes priority', async () => {
    await wrapper.get('[aria-label="收藏Alpha"]').trigger('click')
    await wrapper.get('input').setValue('a')
    wrapper.findComponent(NSelect).vm.$emit('update:value', 'name')
    await wrapper.vm.$nextTick()
    expect(displayedNames()).toEqual(['Bravo', 'Delta', 'Alpha', 'Charlie'])

    await wrapper.findAll('[role="tab"]')[1]!.trigger('click')
    expect(displayedNames()).toEqual(['Alpha', 'Bravo', 'Delta'])
    await wrapper.get('[aria-label="取消收藏Bravo"]').trigger('click')
    expect(displayedNames()).toEqual(['Alpha', 'Delta'])

    await wrapper.findAll('[role="tab"]')[0]!.trigger('click')
    expect(displayedNames()).toEqual(['Bravo', 'Delta', 'Alpha', 'Charlie'])
  })

  it('retains favourite priority when searching and keeps the favourites tab filtered', async () => {
    await wrapper.find('input').setValue('a')
    expect(displayedNames()).toEqual(['Bravo', 'Delta', 'Charlie', 'Alpha'])

    await wrapper.findAll('[role="tab"]')[1]!.trigger('click')
    expect(displayedNames()).toEqual(['Bravo', 'Delta'])
  })
})
