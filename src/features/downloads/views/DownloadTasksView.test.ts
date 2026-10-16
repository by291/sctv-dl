// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { NProgress } from 'naive-ui'

import DownloadTasksView from '@/features/downloads/views/DownloadTasksView.vue'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import StatePanel from '@/shared/components/StatePanel.vue'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'

import type { NativeDownloadPort } from '@/shared/platform/ports'
import type { DownloadTask } from '@shared/contracts/downloads'
import type { VueWrapper } from '@vue/test-utils'

const task: DownloadTask = {
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

let wrapper: VueWrapper | undefined
let pinia: ReturnType<typeof createPinia>

beforeEach(() => {
  pinia = createPinia()
  setActivePinia(pinia)
})

afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
  useDownloadTasksStore().detach()
})

function mountPage(downloads: NativeDownloadPort) {
  const platform = { ...createPlatformFixture(), kind: 'tauri' as const, downloads }
  wrapper = mount(DownloadTasksView, {
    global: { plugins: [pinia], provide: { [platformKey as symbol]: platform } },
  })

  return wrapper
}

function nativeDownloads(): NativeDownloadPort {
  return {
    kind: 'native',
    subscribe: async () => () => {},
    list: async () => [],
    start: async () => ({ kind: 'cancelled' }),
    cancel: async () => {},
    getDirectory: async () => null,
    chooseDirectory: async () => null,
  }
}

it('shows task progress and actions without owning the observation lifecycle', async () => {
  let listener: (value: DownloadTask) => void = () => {}

  const dispose = vi.fn()
  const cancel = vi.fn<NativeDownloadPort['cancel']>().mockResolvedValue(undefined)
  const start = vi.fn<NativeDownloadPort['start']>().mockResolvedValue({
    kind: 'native',
    taskIds: ['retry'],
    usedFallback: false,
    failures: [],
  })
  const downloads: NativeDownloadPort = {
    ...nativeDownloads(),
    subscribe: async (next) => {
      listener = next

      return dispose
    },
    list: async () => [
      task,
      {
        ...task,
        id: 'failed',
        filename: 'clip.mp4',
        state: 'failed',
        quality: 'smooth',
        error: 'Disk full',
      },
      {
        ...task,
        id: 'saved',
        filename: 'saved.mp4',
        state: 'completed',
        receivedBytes: 4096,
        totalBytes: 4096,
      },
    ],
    cancel,
    start,
  }
  const tasks = useDownloadTasksStore()
  await tasks.attach(downloads)
  const page = mountPage(downloads)

  expect(page.text()).toContain('总大小未知')
  expect(page.text()).toContain('Disk full')
  expect(page.text()).toContain('流畅')
  expect(page.findAllComponents(NProgress)).toHaveLength(1)
  expect(page.getComponent(NProgress).props()).toMatchObject({ percentage: 100, status: 'success' })
  await page.get('[aria-label="取消下载news.mp4"]').trigger('click')
  await page.get('[aria-label="重试下载clip.mp4"]').trigger('click')
  await flushPromises()

  expect(cancel).toHaveBeenCalledWith('job')
  expect(start).toHaveBeenCalledWith({
    programmeId: '1',
    dateId: '2',
    contentIds: ['3'],
    quality: 'smooth',
  })
  page.unmount()
  wrapper = undefined
  listener({ ...task, state: 'completed', revision: 3 })

  expect(tasks.tasks[0]?.state).toBe('completed')
  expect(dispose).not.toHaveBeenCalled()
  expect(cancel).toHaveBeenCalledOnce()
})

it('keeps a fully received active transfer below completed progress', async () => {
  const downloads = { ...nativeDownloads(), list: async () => [{ ...task, totalBytes: 1024 }] }
  await useDownloadTasksStore().attach(downloads)
  const page = mountPage(downloads)

  expect(page.getComponent(NProgress).props()).toMatchObject({ percentage: 99, status: 'default' })
})

it('shows loading before the initial snapshot and an empty state only after it resolves', async () => {
  let resolveList: (values: DownloadTask[]) => void = () => {}

  const downloads = {
    ...nativeDownloads(),
    list: () =>
      new Promise<DownloadTask[]>((resolve) => {
        resolveList = resolve
      }),
  }
  const pending = useDownloadTasksStore().attach(downloads)
  const page = mountPage(downloads)
  await flushPromises()

  expect(page.getComponent(StatePanel).props('loading')).toBe(true)
  resolveList([])
  await pending
  await flushPromises()

  expect(page.getComponent(StatePanel).props('title')).toBe('暂无下载任务')
})

it('reconnects a failed observer and replaces its error with the recovered snapshot', async () => {
  const downloads = {
    ...nativeDownloads(),
    subscribe: vi
      .fn<NativeDownloadPort['subscribe']>()
      .mockRejectedValueOnce(new Error('Service offline'))
      .mockResolvedValue(() => {}),
    list: async () => [task],
  }
  await useDownloadTasksStore().attach(downloads)
  const page = mountPage(downloads)
  expect(page.text()).toContain('Service offline')
  expect(page.findComponent(StatePanel).exists()).toBe(false)

  await page.get('button').trigger('click')
  await flushPromises()

  expect(page.text()).not.toContain('Service offline')
  expect(page.get('ul').text()).toContain('news.mp4')
})
