// @vitest-environment happy-dom
import { afterEach, expect, it } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia } from 'pinia'

import SettingsView from '@/features/settings/views/SettingsView.vue'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'

import type { VueWrapper } from '@vue/test-utils'
import type { NativeDownloadPort } from '@/shared/platform/ports'

let wrapper: VueWrapper | undefined
afterEach(() => wrapper?.unmount())

it('keeps browser directory management and offers recoverable native selection', async () => {
  const platform = createPlatformFixture()
  wrapper = mount(SettingsView, {
    global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } },
  })
  await flushPromises()
  expect(wrapper.text()).toContain('浏览器管理')
  expect(wrapper.text()).not.toContain('选择文件夹')
  wrapper.unmount()
  let selected: string | null = null
  platform.downloads = {
    kind: 'native',
    getDirectory: async () => {
      throw new Error('Directory unavailable')
    },
    chooseDirectory: async () => selected,
    list: async () => [],
    subscribe: async () => () => {},
    cancel: async () => {},
    start: async () => ({ kind: 'cancelled' }),
  } satisfies NativeDownloadPort
  platform.capabilities.directorySelection = true
  wrapper = mount(SettingsView, {
    global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } },
  })
  await flushPromises()
  expect(wrapper.text()).toContain('Directory unavailable')
  const choose = () =>
    wrapper!.findAll('button').find((button) => button.text().includes('选择文件夹'))!
  await choose().trigger('click')
  await flushPromises()
  expect(wrapper.text()).toContain('Directory unavailable')
  expect(wrapper.text()).not.toContain('首次下载时会询问')
  selected = '/selected/downloads'
  await choose().trigger('click')
  await flushPromises()
  expect(wrapper.text()).toContain('/selected/downloads')
})

it.each(['success', 'failure'])(
  'ignores stale initial directory %s after a newer selection',
  async (outcome) => {
    const platform = createPlatformFixture()
    let resolve!: (value: string | null) => void
    let reject!: (cause: Error) => void
    const initial = new Promise<string | null>((done, fail) => {
      resolve = done
      reject = fail
    })
    platform.downloads = {
      kind: 'native',
      getDirectory: () => initial,
      chooseDirectory: async () => '/new/directory',
      list: async () => [],
      subscribe: async () => () => {},
      cancel: async () => {},
      start: async () => ({ kind: 'cancelled' }),
    }
    wrapper = mount(SettingsView, {
      global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } },
    })
    await flushPromises()
    await wrapper
      .findAll('button')
      .find((button) => button.text().includes('选择文件夹'))!
      .trigger('click')
    await flushPromises()
    if (outcome === 'success') {
      resolve('/old/directory')
    } else {
      reject(new Error('Obsolete directory error'))
    }

    await flushPromises()
    expect(wrapper.text()).toContain('/new/directory')
    expect(wrapper.text()).not.toContain('/old/directory')
    expect(wrapper.text()).not.toContain('Obsolete directory error')
  },
)
