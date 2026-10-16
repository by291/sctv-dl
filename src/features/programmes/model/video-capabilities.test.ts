import { describe, expect, it } from 'vitest'

import { hasPlayableVideo } from '@/features/programmes/model/video-capabilities'

describe('programme video availability', () => {
  it.each([
    { video: null, smoothVideo: '/smooth.mp4', playable: true },
    { video: '/standard.mp4', smoothVideo: null, playable: true },
    { video: '/standard.mp4', smoothVideo: '/smooth.mp4', playable: true },
    { video: '/same.mp4', smoothVideo: '/same.mp4', playable: true },
    { video: null, smoothVideo: null, playable: false },
  ])('reports availability for $video and $smoothVideo', ({ video, smoothVideo, playable }) => {
    expect(hasPlayableVideo({ video, smoothVideo })).toBe(playable)
  })
})
