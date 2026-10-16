// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { defineComponent } from 'vue'
import { createPinia } from 'pinia'

import { useProgrammeDownloads } from '@/features/programmes/composables/useProgrammeDownloads'
import { useDownloadTasksStore } from '@/features/downloads/stores/useDownloadTasksStore'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'

import type { VueWrapper } from '@vue/test-utils'
import type { DownloadStartResult } from '@shared/contracts/downloads'
import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { NativeDownloadPort } from '@/shared/platform/ports'

const content: ProgrammeContent = {
  id: '3',
  title: 'News',
  cover: null,
  video: 'https://fscgc.scgchc.com/news.mp4',
  smoothVideo: null,
  publishedAt: null,
}

let wrapper: VueWrapper | undefined

afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
})

function mountDownloads(start: NativeDownloadPort['start']) {
  const platform = createPlatformFixture()
  const pinia = createPinia()
  platform.downloads = {
    kind: 'native',
    start,
    list: async () => [],
    subscribe: async () => () => {},
    cancel: async () => {},
    getDirectory: async () => null,
    chooseDirectory: async () => null,
  }

  let downloads!: ReturnType<typeof useProgrammeDownloads>
  wrapper = mount(
    defineComponent({
      setup() {
        downloads = useProgrammeDownloads()

        return () => null
      },
    }),
    { global: { plugins: [pinia], provide: { [platformKey as symbol]: platform } } },
  )

  return { downloads, tasks: useDownloadTasksStore(pinia) }
}

it('exposes native preparation failures before the task panel connects', async () => {
  const { downloads, tasks } = mountDownloads(async (request) => {
    expect(request).toEqual({
      programmeId: '1',
      dateId: '2',
      contentIds: ['3'],
      quality: 'smooth',
    })

    return {
      kind: 'native',
      taskIds: [],
      usedFallback: false,
      failures: [{ contentId: '3', message: 'Content unavailable' }],
    }
  })

  const result = await downloads.prepareDownloads([content], '2', 'smooth', '1')

  expect(result?.kind).toBe('native')
  expect(tasks.failures).toEqual([{ contentId: '3', message: 'Content unavailable' }])
  expect(downloads.preparingIds.value).toEqual([])
})

it('blocks duplicate preparation until directory selection is cancelled, then allows retry', async () => {
  let finish!: (result: DownloadStartResult) => void
  const start = vi
    .fn<NativeDownloadPort['start']>()
    .mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finish = resolve
        }),
    )
    .mockResolvedValue({ kind: 'native', taskIds: ['job'], usedFallback: false, failures: [] })
  const { downloads, tasks } = mountDownloads(start)

  const first = downloads.prepareDownloads([content], '2', 'standard', '1')
  expect(downloads.preparingIds.value).toEqual(['3'])
  expect(await downloads.prepareDownloads([content], '2', 'standard', '1')).toBeNull()
  expect(start).toHaveBeenCalledOnce()

  finish({ kind: 'cancelled' })
  expect(await first).toEqual({ kind: 'cancelled' })
  expect(downloads.preparingIds.value).toEqual([])
  expect(tasks.failures).toEqual([])

  expect(await downloads.prepareDownloads([content], '2', 'standard', '1')).toEqual({
    kind: 'native',
    taskIds: ['job'],
    usedFallback: false,
    failures: [],
  })
})
