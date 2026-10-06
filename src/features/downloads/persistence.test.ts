// @vitest-environment happy-dom
import { beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { nextTick } from 'vue'
import { makeDownloadTask } from './model'
import { useDownloadStore } from './store'
import type { DownloadTask } from './schema'

beforeEach(() => {
  localStorage.clear()
  setActivePinia(createPinia())
})

describe('download queue persistence', () => {
  it('preserves every pending task when restoring more than 1000 entries', async () => {
    const seed = makeDownloadTask(
      {
        id: '1',
        title: '节目',
        cover: null,
        video: 'https://fscgc.scgchc.com/a.mp4',
        smoothVideo: null,
        publishedAt: null,
      },
      '栏目',
      '2026-10-06',
      'standard',
    )
    const tasks: DownloadTask[] = Array.from({ length: 1001 }, (_, index) => ({
      ...seed,
      id: `${index}:standard`,
      contentId: String(index),
      status: index === 0 ? 'failed' : 'queued',
    }))
    localStorage.setItem('sctv-dl:downloads', JSON.stringify(tasks))

    const store = useDownloadStore()
    expect(store.pending).toHaveLength(1001)
    expect(store.tasks[0]?.id).toBe('0:standard')
    await nextTick()
    const saved: DownloadTask[] = JSON.parse(localStorage.getItem('sctv-dl:downloads')!)
    expect(saved).toHaveLength(1001)
    expect(saved[0]?.status).toBe('failed')
    store.$dispose()
  })
})
