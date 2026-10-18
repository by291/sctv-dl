import { describe, expect, it } from 'vitest'

import { programmeSchema, programmeContentSchema } from './programmes.ts'

describe('programme contracts', () => {
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
})
