import { describe, expect, it } from 'vitest'
import { makeDownloadFile } from './model'

const content = {
  id: '2107426129285414913',
  title: '四川新闻联播（2026.10.06）',
  cover: null,
  video: 'https://fscgc.scgchc.com/NewsMedia/a.mp4',
  smoothVideo: null,
  publishedAt: null,
}

describe('download file preparation', () => {
  it('uses the available smooth version when the standard source is missing', () => {
    const onlySmooth = {
      ...content,
      video: null,
      smoothVideo: 'https://fscgc.scgchc.com/NewsMedia/standard/a.mp4',
    }
    const file = makeDownloadFile(onlySmooth, '2026-10-06', 'standard')
    expect(file.quality).toBe('smooth')
    expect(file.url).toBe(onlySmooth.smoothVideo)
  })
  it('falls back to standard when smooth is absent and labels the actual quality', () => {
    const file = makeDownloadFile(content, '2026-10-06', 'smooth')
    expect(file.quality).toBe('standard')
    expect(file.url).toBe(content.video)
    expect(file.filename).toBe('2026-10-06_四川新闻联播（2026.10.06）_标准.mp4')
  })
  it('uses the selected source when both quality versions exist', () => {
    const both = { ...content, smoothVideo: 'https://fscgc.scgchc.com/NewsMedia/standard/a.mp4' }
    expect(makeDownloadFile(both, '2026-10-06', 'standard').url).toBe(content.video)
    expect(makeDownloadFile(both, '2026-10-06', 'smooth').url).toBe(both.smoothVideo)
  })
  it('cleans filenames and uses the selected date', () => {
    const file = makeDownloadFile(
      { ...content, title: '片段:/\\?*\n标题' },
      '2026-10-06',
      'standard',
    )
    expect(file.filename).not.toMatch(/[<>:"/\\|?*\r\n]/)
    expect(file.filename).toContain('2026-10-06')
    expect(file.filename.endsWith('.mp4')).toBe(true)
  })
  it('rejects contents without a playable source', () => {
    expect(() => makeDownloadFile({ ...content, video: null }, '2026-10-06', 'standard')).toThrow(
      '没有可下载的视频',
    )
  })
})
