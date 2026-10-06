import { describe, expect, it } from 'vitest'
import { makeDownloadTask, appendTasks, recoverInterruptedTasks } from './model'
import { downloadTasksSchema } from './schema'

const content = {
  id: '2107426129285414913',
  title: '四川新闻联播（2026.10.06）',
  cover: null,
  video: 'https://fscgc.scgchc.com/NewsMedia/a.mp4',
  smoothVideo: null,
  publishedAt: null,
}

describe('download queue', () => {
  it('uses the available smooth version when the standard source is missing', () => {
    const onlySmooth = {
      ...content,
      video: null,
      smoothVideo: 'https://fscgc.scgchc.com/NewsMedia/standard/a.mp4',
    }
    const task = makeDownloadTask(onlySmooth, '栏目', '2026-10-06', 'standard')
    expect(task.quality).toBe('smooth')
    expect(task.url).toBe(onlySmooth.smoothVideo)
  })
  it('falls back to standard when smooth is absent and deduplicates by actual quality', () => {
    const smooth = makeDownloadTask(content, '四川新闻联播', '2026-10-06', 'smooth')
    const standard = makeDownloadTask(content, '四川新闻联播', '2026-10-06', 'standard')
    expect(smooth.quality).toBe('standard')
    expect(appendTasks([standard], [smooth])).toHaveLength(1)
  })
  it('keeps distinct quality versions as separate tasks', () => {
    const both = { ...content, smoothVideo: 'https://fscgc.scgchc.com/NewsMedia/standard/a.mp4' }
    expect(
      appendTasks(
        [],
        [
          makeDownloadTask(both, '栏目', '2026-10-06', 'standard'),
          makeDownloadTask(both, '栏目', '2026-10-06', 'smooth'),
        ],
      ),
    ).toHaveLength(2)
  })
  it('cleans filenames and uses the selected date', () => {
    const task = makeDownloadTask(
      { ...content, title: '片段:/\\?*\n标题' },
      '栏目',
      '2026-10-06',
      'standard',
    )
    expect(task.filename).not.toMatch(/[<>:"/\\|?*\r\n]/)
    expect(task.filename).toContain('2026-10-06')
    expect(task.filename.endsWith('.mp4')).toBe(true)
  })
  it('recovers damaged storage and resets interrupted preflight to queued', () => {
    expect(downloadTasksSchema.parse({})).toEqual([])
    const task = makeDownloadTask(content, '栏目', '2026-10-06', 'standard')
    expect(recoverInterruptedTasks([{ ...task, status: 'checking' }])[0]?.status).toBe('queued')
    expect(downloadTasksSchema.parse([null, { ...task, url: 'javascript:alert(1)' }])).toEqual([])
  })
})
