import { describe, expect, it } from 'vitest'
import { getVideoVariants, resolveVideo } from './video'

const content = {
  id: '1',
  title: '节目',
  cover: null,
  publishedAt: null,
  video: null,
  smoothVideo: 'https://fscgc.scgchc.com/NewsMedia/standard/a.mp4',
}
describe('shared preview and download availability', () => {
  it('allows smooth-only rows in previews and selection with either preference', () => {
    expect(resolveVideo(content, 'smooth')).toEqual({ quality: 'smooth', url: content.smoothVideo })
    expect(resolveVideo(content, 'standard')).toEqual({
      quality: 'smooth',
      url: content.smoothVideo,
    })
  })
  it('disables content only when both variants are absent', () => {
    expect(resolveVideo({ ...content, smoothVideo: null }, 'smooth')).toBeNull()
  })

  it('lists distinct standard and smooth files for the player quality menu', () => {
    const video = 'https://fscgc.scgchc.com/full.mp4'

    expect(getVideoVariants({ ...content, video })).toEqual([
      { quality: 'standard', url: video },
      { quality: 'smooth', url: content.smoothVideo },
    ])
    expect(getVideoVariants({ ...content, video, smoothVideo: video })).toEqual([
      { quality: 'standard', url: video },
    ])
  })

  it('offers only existing variants and leaves unavailable content without a choice', () => {
    expect(getVideoVariants(content)).toEqual([{ quality: 'smooth', url: content.smoothVideo }])
    expect(getVideoVariants({ ...content, smoothVideo: null })).toEqual([])
  })
})
