import { describe, expect, it } from 'vitest'

import { programmeSchema, programmeContentSchema } from './programmes.ts'
import { downloadRequestSchema, downloadTaskSchema } from './downloads.ts'
import { settingsSchema } from './settings.ts'
import settings from '../fixtures/settings.json' with { type: 'json' }

describe('application contracts', () => {
  it('retains string IDs above the safe integer boundary and rejects numeric DTO IDs', () => {
    expect(programmeSchema.parse({ id: '9007199254740992', name: 'News', cover: null }).id).toBe(
      '9007199254740992',
    )
    expect(programmeSchema.safeParse({ id: 1, name: 'News', cover: null }).success).toBe(false)
  })

  it('accepts normalized nullable variants without interpreting upstream field names', () => {
    const result = programmeContentSchema.parse({
      id: '1',
      title: 'News',
      cover: null,
      video: null,
      smoothVideo: 'https://fscgc.scgchc.com/smooth.mp4',
      publishedAt: null,
    })
    expect(result.video).toBeNull()
    expect(result.smoothVideo).toBe('https://fscgc.scgchc.com/smooth.mp4')
    expect(
      programmeContentSchema.safeParse({ ...result, cover: 'javascript:alert(1)' }).success,
    ).toBe(false)
  })

  it('limits distinct batch IDs and refuses caller-supplied file locations', () => {
    const request = { programmeId: '1', dateId: '2', contentIds: ['3', '3'], quality: 'standard' }
    expect(downloadRequestSchema.parse(request).contentIds).toEqual(['3'])
    expect(
      downloadRequestSchema.safeParse({ ...request, url: 'https://example.com/a.mp4' }).success,
    ).toBe(false)
    expect(
      downloadRequestSchema.safeParse({
        ...request,
        contentIds: Array.from({ length: 101 }, (_, i) => String(i)),
      }).success,
    ).toBe(false)
  })

  it('preserves unknown transfer totals and rejects negative progress', () => {
    const task = {
      id: 'task-1',
      content: { programmeId: '1', dateId: '2', contentId: '3' },
      filename: 'news.mp4',
      quality: 'standard',
      state: 'running',
      receivedBytes: 10,
      totalBytes: null,
      error: null,
      revision: 1,
    }
    expect(downloadTaskSchema.parse(task).totalBytes).toBeNull()
    expect(downloadTaskSchema.safeParse({ ...task, receivedBytes: -1 }).success).toBe(false)
  })

  it.each(settings)('retains preference defaults and valid favourite IDs', (fixture) => {
    expect(settingsSchema.parse(fixture.raw)).toEqual(fixture.expected)
  })
})
