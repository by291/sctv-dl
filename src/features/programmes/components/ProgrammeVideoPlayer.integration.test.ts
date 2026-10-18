// @vitest-environment happy-dom
import { expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

it('initializes real Artplayer quality controls without reporting a media failure', async () => {
  // Browsers queue media events; happy-dom emits canplay synchronously from the src setter.
  const source = vi.spyOn(HTMLMediaElement.prototype, 'src', 'set').mockImplementation(function (
    this: HTMLMediaElement,
    value: string,
  ) {
    this.setAttribute('src', value)
  })
  const wrapper = mount(ProgrammeVideoPlayer, {
    attachTo: document.body,
    props: {
      url: '/standard.mp4',
      poster: null,
      title: 'Programme preview',
      variants: [
        { quality: 'standard', url: '/standard.mp4' },
        { quality: 'smooth', url: '/smooth.mp4' },
      ],
    },
  })

  try {
    await flushPromises()
    expect(wrapper.emitted('error')).toBeUndefined()
    expect(wrapper.get('.art-control-quality').text()).toContain('标准')
    expect(wrapper.get('.art-control-quality').text()).toContain('流畅')

    const video = wrapper.get('video').element
    Object.defineProperty(video, 'duration', { value: 1440, configurable: true })
    video.dispatchEvent(new Event('loadedmetadata'))

    expect(wrapper.emitted('ready')).toHaveLength(1)
    expect(wrapper.vm.capture()).toMatchObject({ durationMs: 1440000, initialized: true })
  } finally {
    wrapper.unmount()
    source.mockRestore()
  }
})
