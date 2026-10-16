// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'

import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

const props = { url: '/video.mp4', poster: null, title: 'Programme preview' }

beforeEach(() => {
  // Native media events are asynchronous; happy-dom fires loadstart inside the src setter.
  vi.spyOn(HTMLMediaElement.prototype, 'src', 'set').mockImplementation(function (
    this: HTMLMediaElement,
    value: string,
  ) {
    this.setAttribute('src', value)
  })
})

afterEach(() => {
  vi.restoreAllMocks()
})

describe('programme player media readiness', () => {
  it('offers playback when a paused WebView loads metadata without firing canplay', () => {
    const wrapper = mount(ProgrammeVideoPlayer, { props, attachTo: document.body })

    try {
      const video = wrapper.get('video').element as HTMLVideoElement
      const surface = wrapper.get('.art-video-player')

      video.dispatchEvent(new Event('loadstart'))
      expect(surface.classes()).toContain('art-loading-show')

      Object.defineProperty(video, 'readyState', { value: 1, configurable: true })
      video.dispatchEvent(new Event('loadedmetadata'))
      video.dispatchEvent(new Event('suspend'))

      expect(surface.classes()).not.toContain('art-loading-show')
      expect(surface.classes()).toContain('art-mask-show')
      expect(video.paused).toBe(true)
      expect(video.preload).toBe('metadata')
      expect(wrapper.emitted('ready')).toEqual([[]])
    } finally {
      wrapper.unmount()
    }
  })

  it('clears buffering when playback resumes without another canplay event', () => {
    const wrapper = mount(ProgrammeVideoPlayer, { props, attachTo: document.body })

    try {
      const video = wrapper.get('video').element as HTMLVideoElement
      const surface = wrapper.get('.art-video-player')

      video.dispatchEvent(new Event('canplay'))
      video.dispatchEvent(new Event('waiting'))
      expect(surface.classes()).toContain('art-loading-show')

      Object.defineProperty(video, 'paused', { value: false, configurable: true })
      video.dispatchEvent(new Event('playing'))

      expect(surface.classes()).not.toContain('art-loading-show')

      video.dispatchEvent(new Event('waiting'))
      expect(surface.classes()).toContain('art-loading-show')
    } finally {
      wrapper.unmount()
    }
  })

  it.each([
    { state: 'playing', paused: false, seeking: false },
    { state: 'seeking', paused: true, seeking: true },
  ])('keeps loading feedback when metadata arrives while $state', ({ paused, seeking }) => {
    const wrapper = mount(ProgrammeVideoPlayer, { props, attachTo: document.body })

    try {
      const video = wrapper.get('video').element as HTMLVideoElement
      const surface = wrapper.get('.art-video-player')

      video.dispatchEvent(new Event('loadstart'))
      Object.defineProperties(video, {
        paused: { value: paused, configurable: true },
        seeking: { value: seeking, configurable: true },
      })
      video.dispatchEvent(new Event('loadedmetadata'))

      expect(surface.classes()).toContain('art-loading-show')
    } finally {
      wrapper.unmount()
    }
  })
})
