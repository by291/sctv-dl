// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NSelect } from 'naive-ui'

import LibraryView from './LibraryView.vue'
import { useProgrammeStore } from '../store'
import { useSettingsStore } from '../../settings/store'

import type { VueWrapper } from '@vue/test-utils'

let wrapper: VueWrapper

beforeEach(async () => {
  localStorage.clear()
  const pinia = createPinia()
  setActivePinia(pinia)
  useProgrammeStore().programmes = [
    { id: 'c', name: 'Charlie', cover: null },
    { id: 'b', name: 'Bravo', cover: null },
    { id: 'a', name: 'Alpha', cover: null },
    { id: 'd', name: 'Delta', cover: null },
  ]
  useSettingsStore().favourites = ['d', 'b']
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: LibraryView },
      { path: '/programmes/:id', component: () => import('./ProgrammeView.vue') },
    ],
  })
  await router.push('/')
  await router.isReady()
  wrapper = mount(LibraryView, { global: { plugins: [pinia, router] } })
})

afterEach(() => {
  wrapper.unmount()
  useProgrammeStore().$dispose()
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
    expect(useProgrammeStore().programmes.map((programme) => programme.id)).toEqual([
      'c',
      'b',
      'a',
      'd',
    ])
  })

  it('updates the priority immediately when a programme is starred or unstarred', async () => {
    await wrapper.find('[aria-label="收藏Charlie"]').trigger('click')
    expect(displayedNames()).toEqual(['Charlie', 'Bravo', 'Delta', 'Alpha'])

    await wrapper.find('[aria-label="取消收藏Bravo"]').trigger('click')
    expect(displayedNames()).toEqual(['Charlie', 'Delta', 'Bravo', 'Alpha'])
  })

  it('retains favourite priority when searching and keeps the favourites tab filtered', async () => {
    await wrapper.find('input').setValue('a')
    expect(displayedNames()).toEqual(['Bravo', 'Delta', 'Charlie', 'Alpha'])

    await wrapper.findAll('[role="tab"]')[1]!.trigger('click')
    expect(displayedNames()).toEqual(['Bravo', 'Delta'])
  })
})
