// @vitest-environment happy-dom
import { createNativeDownloadFixture } from '@/shared/platform/platform.test-support'
import { afterEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia } from 'pinia'
import { NButton, NPopconfirm } from 'naive-ui'

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
    ...createNativeDownloadFixture(),
    kind: 'native',
    getDirectory: async () => {
      throw new Error('Directory unavailable')
    },
    chooseDirectory: async () => selected,
    start: async () => ({ kind: 'cancelled' }),
  } satisfies NativeDownloadPort
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
      ...createNativeDownloadFixture(),
      kind: 'native',
      getDirectory: () => initial,
      chooseDirectory: async () => '/new/directory',
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

it('clears only programme metadata after confirmation and keeps user data', async () => {
  const platform = createPlatformFixture()
  let clears = 0
  platform.programmeCache.clear = async () => {
    clears += 1

    return { epoch: 'next' }
  }

  const pinia = createPinia()
  wrapper = mount(SettingsView, {
    global: { plugins: [pinia], provide: { [platformKey as symbol]: platform } },
  })
  await flushPromises()
  const action = wrapper.findAll('button').find((button) => button.text() === '清除节目缓存')
  expect(action).toBeDefined()
  await action!.trigger('click')
  expect(clears).toBe(0)
  const confirm = wrapper
    .findAllComponents(NPopconfirm)
    .find((component) => component.text().includes('清除节目缓存'))!
  confirm.vm.$emit('positive-click')
  await flushPromises()
  expect(clears).toBe(1)
  expect(wrapper.text()).toContain('节目缓存已清除')
})

it('discloses a failed refresh while keeping the previously loaded catalogue usable', async () => {
  const platform = createPlatformFixture()
  platform.programmes.programmes = vi
    .fn()
    .mockResolvedValueOnce([{ id: '1', name: 'News', cover: null }])
    .mockRejectedValueOnce(new Error('Programme service offline'))
  wrapper = mount(SettingsView, {
    global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } },
  })
  await flushPromises()

  await wrapper
    .findAll('button')
    .find((button) => button.text() === '检查连接')!
    .trigger('click')
  await flushPromises()

  expect(wrapper.text()).toContain('Programme service offline')
  expect(wrapper.text()).not.toContain('已连接')
  expect(wrapper.get('.connection-status').classes()).toContain('offline')
})

it('shows a pending refresh even when a usable catalogue is already present', async () => {
  const platform = createPlatformFixture()
  let complete!: (value: []) => void
  platform.programmes.programmes = vi
    .fn()
    .mockResolvedValueOnce([])
    .mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          complete = resolve
        }),
    )
  wrapper = mount(SettingsView, {
    global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } },
  })
  await flushPromises()

  const refresh = wrapper.findAllComponents(NButton).find((button) => button.text() === '检查连接')!
  await refresh.trigger('click')
  await flushPromises()
  expect(refresh.props('loading')).toBe(true)

  complete([])
  await flushPromises()
  expect(refresh.props('loading')).toBe(false)
})

it('identifies cached data without claiming a successful live connection', async () => {
  const platform = createPlatformFixture()
  platform.programmeCache.read = async () => ({
    epoch: 'fixture',
    persisted: true,
    warning: null,
    snapshot: {
      kind: 'catalogue',
      version: 1,
      revision: 'saved',
      fetchedAt: '2026-10-17T00:00:00Z',
      items: [{ id: '1', name: 'Cached news', cover: null }],
    },
  })
  let complete!: (value: []) => void
  platform.programmes.programmes = () =>
    new Promise((resolve) => {
      complete = resolve
    })
  wrapper = mount(SettingsView, {
    global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } },
  })
  await flushPromises()

  expect(wrapper.get('.connection-status').element.parentElement?.textContent).toContain('缓存')
  expect(wrapper.text()).not.toContain('已连接')

  complete([])
  await flushPromises()
})
