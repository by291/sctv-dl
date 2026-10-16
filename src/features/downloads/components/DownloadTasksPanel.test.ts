// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia } from 'pinia'
import DownloadTasksPanel from '@/features/downloads/components/DownloadTasksPanel.vue'
import type { NativeDownloadPort } from '@/shared/platform/ports'
import type { DownloadTask } from '@shared/contracts/downloads'
import type { VueWrapper } from '@vue/test-utils'

let wrapper: VueWrapper | undefined
afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
  document.body.innerHTML = ''
})

it('shows truthful progress, errors, and actions and detaches without cancelling jobs', async () => {
  const dispose = vi.fn()
  const cancel = vi.fn().mockResolvedValue(undefined)
  const start = vi
    .fn()
    .mockResolvedValue({ kind: 'native', taskIds: ['retry'], usedFallback: false, failures: [] })
  const base: DownloadTask = {
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
  const downloads = {
    kind: 'native',
    subscribe: async () => dispose,
    list: async () => [
      base,
      {
        ...base,
        id: 'failed',
        filename: 'clip.mp4',
        state: 'failed',
        quality: 'smooth',
        error: 'Disk full',
      },
    ],
    cancel,
    start,
  } as unknown as NativeDownloadPort
  wrapper = mount(DownloadTasksPanel, {
    attachTo: document.body,
    props: { downloads },
    global: { plugins: [createPinia()] },
  })
  await flushPromises()
  await wrapper.get('button').trigger('click')
  await flushPromises()
  expect(document.body.textContent).toContain('总大小未知')
  expect(document.body.textContent).toContain('Disk full')
  expect(document.body.textContent).toContain('流畅')
  const buttons = [...document.body.querySelectorAll('button')]
  buttons.find((button) => button.textContent?.trim() === '取消')!.click()
  await flushPromises()
  expect(cancel).toHaveBeenCalledWith('job')
  buttons.find((button) => button.textContent?.trim() === '重试')!.click()
  await flushPromises()
  expect(start).toHaveBeenCalledWith({
    programmeId: '1',
    dateId: '2',
    contentIds: ['3'],
    quality: 'smooth',
  })
  wrapper.unmount()
  wrapper = undefined
  expect(dispose).toHaveBeenCalledOnce()
  expect(cancel).toHaveBeenCalledOnce()
})
