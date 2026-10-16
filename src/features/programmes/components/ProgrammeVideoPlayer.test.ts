// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'

import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

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

  it('puts the supplied variants in the bottom quality menu with the current source selected', () => {
    const wrapper = mount(ProgrammeVideoPlayer, {
      props: {
        ...props,
        url: '/media?url=smooth.mp4',
        variants: [
          { quality: 'standard', url: props.url },
          { quality: 'smooth', url: '/media?url=smooth.mp4' },
        ],
      },
    })
    expect(createPlayer.mock.calls[0]?.[0].quality).toEqual([
      { html: '标准', url: props.url, default: false },
      { html: '流畅', url: '/media?url=smooth.mp4', default: true },
    ])
    wrapper.unmount()
  })

  it('omits the quality menu when there is no alternative source', () => {
    const wrapper = mount(ProgrammeVideoPlayer, {
      props: { ...props, variants: [{ quality: 'standard', url: props.url }] },
    })

    expect(createPlayer.mock.calls[0]?.[0].quality).toEqual([])
    wrapper.unmount()
  })
})

it('omits unsupported native controls instead of advertising unavailable APIs', () => {
  const wrapper = mount(ProgrammeVideoPlayer, { props })
  expect(createPlayer.mock.calls[0]?.[0].pip).toBe(false)
  expect(createPlayer.mock.calls[0]?.[0].fullscreen).toBe(false)
  wrapper.unmount()
})

it('keeps WebKit picture-in-picture available when the standard API is absent', () => {
  const supports = vi.fn(() => true)
  Object.defineProperty(HTMLVideoElement.prototype, 'webkitSupportsPresentationMode', {
    value: supports,
    configurable: true,
  })
  Object.defineProperty(HTMLVideoElement.prototype, 'webkitSetPresentationMode', {
    value: vi.fn(),
    configurable: true,
  })
  try {
    const wrapper = mount(ProgrammeVideoPlayer, { props })
    expect(createPlayer.mock.calls[0]?.[0].pip).toBe(true)
    expect(supports).toHaveBeenCalledWith('picture-in-picture')
    wrapper.unmount()
  } finally {
    Reflect.deleteProperty(HTMLVideoElement.prototype, 'webkitSupportsPresentationMode')
    Reflect.deleteProperty(HTMLVideoElement.prototype, 'webkitSetPresentationMode')
  }
})
