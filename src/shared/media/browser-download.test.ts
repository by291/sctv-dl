import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { handOffDownload } from '@/shared/media/browser-download'

const click = vi.fn()
beforeEach(() => {
  vi.stubGlobal('document', {
    createElement: () => ({ click, remove: vi.fn() }),
    body: { append: vi.fn() },
  })
  click.mockClear()
})
afterEach(() => vi.unstubAllGlobals())
const file = {
  url: 'https://fscgc.scgchc.com/a.mp4',
  filename: '2026-10-06_节目_标准.mp4',
}

describe('browser download handoff', () => {
  it('does not mistake a static host HTML fallback for a download proxy', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response('', { headers: { 'content-type': 'text/html' } })),
    )
    await expect(handOffDownload(file)).rejects.toThrow('下载代理未返回视频')
    expect(click).not.toHaveBeenCalled()
  })
  it('rejects an HTTP failure and permits a successful browser handoff on retry', async () => {
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
    await expect(handOffDownload(file)).rejects.toThrow('HTTP 403')
    expect(click).not.toHaveBeenCalled()
    await handOffDownload(file)
    expect(click).toHaveBeenCalledTimes(1)
    expect(fetcher).toHaveBeenLastCalledWith(
      '/media?url=https%3A%2F%2Ffscgc.scgchc.com%2Fa.mp4&download=1&filename=2026-10-06_%E8%8A%82%E7%9B%AE_%E6%A0%87%E5%87%86.mp4',
      expect.objectContaining({ method: 'HEAD' }),
    )
  })
})
