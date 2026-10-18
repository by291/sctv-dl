// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { NProgress, NCheckbox, NDropdown, NModal } from 'naive-ui'

import DownloadTasksView from '@/features/downloads/views/DownloadTasksView.vue'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import StatePanel from '@/shared/components/StatePanel.vue'
import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import {
  createPlatformFixture,
  createDownloadTaskFixture,
  createNativeDownloadFixture,
} from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'

import type { NativeDownloadPort } from '@/shared/platform/ports'
import type { DownloadEvent, DownloadSnapshot } from '@shared/contracts/downloads'
import type { VueWrapper } from '@vue/test-utils'

const task = createDownloadTaskFixture()
let wrapper: VueWrapper | undefined
let pinia: ReturnType<typeof createPinia>
beforeEach(() => {
  pinia = createPinia()
  setActivePinia(pinia)
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
})
afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
  useDownloadTasksStore().detach()
  vi.restoreAllMocks()
})

function mountPage(downloads: NativeDownloadPort) {
  const platform = { ...createPlatformFixture(), kind: 'tauri' as const, downloads }
  wrapper = mount(DownloadTasksView, {
    global: {
      plugins: [pinia],
      provide: { [platformKey as symbol]: platform },
      stubs: { ProgrammePreviewDialog: true },
    },
  })

  return wrapper
}

it('shows unknown totals and handles the current attempt without owning observation', async () => {
  const port = createNativeDownloadFixture()
  const dispose = vi.fn()
  port.subscribeEvents = async () => dispose
  port.snapshot = async () => ({
    epoch: 'one',
    revision: 2,
    tasks: [
      task,
      {
        ...task,
        id: 'saved',
        filename: 'saved.mp4',
        state: 'completed',
        receivedBytes: 4096,
        totalBytes: 4096,
        fileAvailable: true,
        hasPartial: false,
      },
    ],
  })
  port.act = vi.fn<NativeDownloadPort['act']>(async () => ({
    kind: 'applied',
    task: { ...task, state: 'paused', revision: 3 },
  }))
  await useDownloadTasksStore().attach(port)
  const page = mountPage(port)
  expect(page.text()).toContain('总大小未知')
  expect(page.findAllComponents(NProgress)).toHaveLength(0)
  await page.get('[aria-label="暂停：news.mp4"]').trigger('click')
  await flushPromises()
  expect(port.act).toHaveBeenCalledWith({
    taskId: 'job',
    attemptId: task.attemptId,
    action: 'pause',
  })
  await page.get('[aria-label="播放本地文件：saved.mp4"]').trigger('click')
  expect(page.getComponent(ProgrammePreviewDialog).props('input')).toMatchObject({
    kind: 'download',
    taskId: 'saved',
  })
  page.unmount()
  wrapper = undefined
  expect(dispose).not.toHaveBeenCalled()
})

it('keeps active full-byte progress below completion', async () => {
  const port = createNativeDownloadFixture()
  port.snapshot = async () => ({
    epoch: 'one',
    revision: 2,
    tasks: [{ ...task, totalBytes: 1024 }],
  })
  await useDownloadTasksStore().attach(port)
  expect(mountPage(port).getComponent(NProgress).props()).toMatchObject({
    percentage: 99,
    status: 'default',
  })
})

it('shows loading until snapshot resolution and supports a recoverable observer failure', async () => {
  const port = createNativeDownloadFixture()
  let resolve!: (snapshot: DownloadSnapshot) => void
  port.snapshot = () =>
    new Promise((done) => {
      resolve = done
    })
  const pending = useDownloadTasksStore().attach(port)
  const page = mountPage(port)
  await flushPromises()
  expect(page.getComponent(StatePanel).props('loading')).toBe(true)
  resolve({ epoch: 'one', revision: 0, tasks: [] })
  await pending
  await flushPromises()
  expect(page.getComponent(StatePanel).props('title')).toBe('暂无下载任务')
  port.subscribeEvents = async () => {
    throw new Error('Service offline')
  }

  await useDownloadTasksStore().attach(port)
  await flushPromises()
  expect(page.text()).toContain('Service offline')
  port.subscribeEvents = async () => () => {}

  port.snapshot = async () => ({ epoch: 'one', revision: 2, tasks: [task] })
  await page
    .findAll('button')
    .find((button) => button.text() === '重新连接')!
    .trigger('click')
  await flushPromises()
  expect(page.text()).not.toContain('Service offline')
})

it('clears selection when filters change and confirms file deletion separately from record removal', async () => {
  const port = createNativeDownloadFixture()
  port.snapshot = async () => ({
    epoch: 'one',
    revision: 2,
    tasks: [{ ...task, state: 'completed', fileAvailable: true, hasPartial: false }],
  })
  port.act = vi.fn<NativeDownloadPort['act']>(async () => ({ kind: 'applied', task: null }))
  await useDownloadTasksStore().attach(port)
  const page = mountPage(port)
  page.findAllComponents(NCheckbox)[0]!.vm.$emit('update:checked', true)
  await flushPromises()
  expect(page.find('[aria-label="批量删除文件"]').exists()).toBe(true)
  await page.get('.download-filter[aria-pressed="true"]').trigger('click')
  expect(page.find('[aria-label="批量删除文件"]').exists()).toBe(true)
  await page
    .findAll('.download-filter')
    .find((button) => button.text().includes('已完成'))!
    .trigger('click')
  await flushPromises()
  expect(page.find('[aria-label="批量删除文件"]').exists()).toBe(false)
  page.getComponent(NDropdown).vm.$emit('select', 'deleteFile')
  await flushPromises()
  expect(port.act).not.toHaveBeenCalled()
  const confirmation = page.findAllComponents(NModal).find((component) => component.props('show'))!
  confirmation.vm.$emit('positive-click')
  await flushPromises()
  expect(port.act).toHaveBeenCalledWith({
    taskId: task.id,
    attemptId: task.attemptId,
    action: 'deleteFile',
  })
})

it('offers direct batch actions only for applicable selected tasks and confirms destructive actions', async () => {
  const port = createNativeDownloadFixture()
  port.snapshot = async () => ({
    epoch: 'one',
    revision: 2,
    tasks: [
      task,
      { ...task, id: 'saved', state: 'completed', fileAvailable: true, hasPartial: false },
    ],
  })
  port.act = vi.fn<NativeDownloadPort['act']>(async () => ({ kind: 'applied', task: null }))
  await useDownloadTasksStore().attach(port)
  const page = mountPage(port)
  page.findAllComponents(NCheckbox)[0]!.vm.$emit('update:checked', true)
  await flushPromises()

  expect(page.find('[aria-label="批量暂停"]').exists()).toBe(true)
  expect(page.find('[aria-label="批量继续下载"]').exists()).toBe(false)
  await page.get('[aria-label="批量删除文件"]').trigger('click')
  expect(port.act).not.toHaveBeenCalled()
  page
    .findAllComponents(NModal)
    .find((component) => component.props('show'))!
    .vm.$emit('positive-click')
  await flushPromises()

  expect(port.act).toHaveBeenCalledExactlyOnceWith({
    taskId: 'saved',
    attemptId: task.attemptId,
    action: 'deleteFile',
  })
  expect(page.get('[role="status"]').text()).toContain('已处理 1 个')
  page.findAllComponents(NCheckbox)[0]!.vm.$emit('update:checked', false)
  await flushPromises()
  expect(page.find('[aria-label="批量暂停"]').exists()).toBe(false)
})

it('keeps batch confirmation tied to the captured attempt after a transfer restarts', async () => {
  const port = createNativeDownloadFixture()
  let receive!: (event: DownloadEvent) => void
  port.subscribeEvents = async (listener) => {
    receive = listener

    return () => {}
  }

  port.snapshot = async () => ({ epoch: 'one', revision: 2, tasks: [task] })
  port.act = vi.fn<NativeDownloadPort['act']>()
  await useDownloadTasksStore().attach(port)
  const page = mountPage(port)
  page.findAllComponents(NCheckbox)[0]!.vm.$emit('update:checked', true)
  await flushPromises()
  await page.get('[aria-label="批量取消下载"]').trigger('click')

  receive({
    kind: 'upsert',
    epoch: 'one',
    revision: 3,
    task: { ...task, attemptId: 'replacement', revision: 3 },
  })
  page
    .findAllComponents(NModal)
    .find((component) => component.props('show'))!
    .vm.$emit('positive-click')
  await flushPromises()

  expect(port.act).not.toHaveBeenCalled()
  expect(page.get('[role="status"]').text()).toContain('跳过 1 个')
})
