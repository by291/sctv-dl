// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

import ProgrammeVideoPlayer from './ProgrammeVideoPlayer.vue'

const { createPlayer } = vi.hoisted(() => ({ createPlayer: vi.fn() }))

vi.mock('artplayer', () => ({
  default: class {
    constructor(options: unknown) {
      return createPlayer(options)
    }
  },
}))

const player = {
  pause: vi.fn(),
  destroy: vi.fn(),
  on: vi.fn(),
  switchQuality: vi.fn().mockResolvedValue(undefined),
}
const props = { url: '/media?url=video.mp4', poster: null, title: 'Programme preview' }

beforeEach(() => {
  vi.clearAllMocks()
  createPlayer.mockReturnValue(player)
})

describe('programme player lifecycle', () => {
  it('pauses and destroys the player when the preview is unmounted', () => {
    const wrapper = mount(ProgrammeVideoPlayer, { props })

    expect(createPlayer).toHaveBeenCalledOnce()
    wrapper.unmount()

    expect(player.pause).toHaveBeenCalledOnce()
    expect(player.destroy).toHaveBeenCalledOnce()
  })

  it('reports video errors to the preview dialog', () => {
    const wrapper = mount(ProgrammeVideoPlayer, { props })
    const listener = player.on.mock.calls.find(([event]) => event === 'video:error')?.[1]

    expect(listener).toBeTypeOf('function')
    listener()
    expect(wrapper.emitted('error')).toEqual([[]])
    wrapper.unmount()
  })

  it('reports initialization failures without leaving an instance to destroy', () => {
    createPlayer.mockImplementationOnce(() => {
      throw new Error('Player initialization failed')
    })
    const wrapper = mount(ProgrammeVideoPlayer, { props })

    expect(wrapper.emitted('error')).toEqual([[]])
    wrapper.unmount()
    expect(player.destroy).not.toHaveBeenCalled()
  })

  it('switches only to supplied variants using the progress-preserving player API', async () => {
    const wrapper = mount(ProgrammeVideoPlayer, {
      props: {
        ...props,
        variants: [
          { quality: 'standard', url: props.url },
          { quality: 'smooth', url: '/media?url=smooth.mp4' },
        ],
      },
    })
    const settings = createPlayer.mock.calls[0]?.[0].settings
    expect(settings).toHaveLength(1)
    expect(settings[0].selector).toEqual([
      { html: '标准', url: props.url, default: true },
      { html: '流畅', url: '/media?url=smooth.mp4', default: false },
    ])
    settings[0].onSelect(settings[0].selector[1])
    await flushPromises()
    expect(player.switchQuality).toHaveBeenCalledWith('/media?url=smooth.mp4')
    wrapper.unmount()
  })
})
