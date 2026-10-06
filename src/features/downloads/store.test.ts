import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useDownloadStore } from './store'
import { makeDownloadTask } from './model'

const click = vi.fn()
beforeEach(() => {
  setActivePinia(createPinia())
  vi.stubGlobal('localStorage', { getItem: () => null, setItem: vi.fn() })
  vi.stubGlobal('document', {
    createElement: () => ({ click, remove: vi.fn() }),
    body: { append: vi.fn() },
  })
  click.mockClear()
})
afterEach(() => vi.unstubAllGlobals())
const seed = () => {
  const store = useDownloadStore()
  const task = makeDownloadTask(
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
  store.add([task])

  return { store, task }
}

describe('browser download handoff', () => {
  it('does not mistake a static host HTML fallback for a download proxy', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response('', { headers: { 'content-type': 'text/html' } })),
    )
    const { store, task } = seed()
    await store.start(task.id)
    expect(store.tasks[0]?.status).toBe('failed')
    expect(click).not.toHaveBeenCalled()
  })
  it('reports HTTP failure and allows a successful retry without claiming file completion', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(new Response('', { status: 403 }))
      .mockResolvedValueOnce(
        new Response('', {
          headers: {
            'content-type': 'video/mp4',
            'content-disposition': 'attachment; filename="test.mp4"',
          },
        }),
      )
    vi.stubGlobal('fetch', fetcher)
    const { store, task } = seed()
    await store.start(task.id)
    expect(store.tasks[0]?.status).toBe('failed')
    await store.start(task.id)
    expect(store.tasks[0]?.status).toBe('handed-off')
    expect(click).toHaveBeenCalledTimes(1)
  })
})
