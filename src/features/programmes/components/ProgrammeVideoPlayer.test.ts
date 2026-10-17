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
  controls: { update: vi.fn() },
  switchQuality: vi.fn(),
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
    expect(player.controls.update.mock.calls[0]?.[0].selector).toEqual([
      { html: '标准', url: props.url, default: false },
      { html: '流畅', url: '/media?url=smooth.mp4', default: true },
    ])
    wrapper.unmount()
  })

  it('omits the quality menu when there is no alternative source', () => {
    const wrapper = mount(ProgrammeVideoPlayer, {
      props: { ...props, variants: [{ quality: 'standard', url: props.url }] },
    })

    expect(player.controls.update).not.toHaveBeenCalled()
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

function mediaPlayer() {
  return {
    ...player,
    video: {
      currentTime: 0,
      duration: 600,
      playbackRate: 1,
      paused: true,
      seeking: false,
      ended: false,
      currentSrc: props.url,
      error: null,
      play: vi.fn().mockResolvedValue(undefined),
    },
    loading: { show: true },
    mask: { show: false },
  }
}

function fire(event: string) {
  player.on.mock.calls.find(([name]) => name === `video:${event}`)?.[1]()
}

it('restores paused progress only after the native seek settles', () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, {
    props: { ...props, restore: { positionMs: 300000, speed: 1.5, playing: false } },
  })

  fire('loadedmetadata')
  expect(media.video.currentTime).toBe(300)
  expect(media.video.playbackRate).toBe(1.5)
  expect(wrapper.vm.capture()?.initialized).toBe(false)
  expect(media.video.play).not.toHaveBeenCalled()

  fire('seeked')
  expect(wrapper.vm.capture()).toMatchObject({
    positionMs: 300000,
    speed: 1.5,
    playing: false,
    initialized: true,
  })
  wrapper.unmount()
})

it('blocks retry autoplay when the preview becomes inactive during restoration', async () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, {
    props: { ...props, restore: { positionMs: 300000, speed: 1.5, playing: true }, active: true },
  })
  fire('loadedmetadata')
  await wrapper.setProps({ active: false })
  fire('seeked')
  expect(media.video.play).not.toHaveBeenCalled()
  wrapper.unmount()
})

it('reports the actual selected quality and tolerates rejected autoplay', async () => {
  const media = mediaPlayer()
  media.video.currentSrc = '/smooth.mp4'
  media.video.play.mockRejectedValue(new Error('Autoplay denied'))
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, {
    props: {
      ...props,
      restore: { positionMs: 0, speed: 1, playing: true },
      variants: [
        { quality: 'standard', url: props.url },
        { quality: 'smooth', url: '/smooth.mp4' },
      ],
    },
  })
  fire('loadedmetadata')
  await Promise.resolve()
  await Promise.resolve()
  expect(wrapper.vm.capture()).toMatchObject({
    quality: 'smooth',
    playing: false,
    initialized: true,
  })
  wrapper.unmount()
})

it('clamps restored progress to loaded duration and resumes only after seeked', async () => {
  const media = mediaPlayer()
  media.video.duration = 120
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, {
    props: { ...props, restore: { positionMs: 300000, speed: 1.5, playing: true } },
  })
  fire('loadedmetadata')
  expect(media.video.currentTime).toBe(120)
  expect(media.video.play).not.toHaveBeenCalled()
  fire('seeked')
  expect(media.video.play).toHaveBeenCalledOnce()
  wrapper.unmount()
})

it('keeps the last usable sample after an error even if reconnect emits metadata at zero', () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, { props })
  fire('loadedmetadata')
  media.video.currentTime = 300
  fire('timeupdate')
  media.video.currentTime = 0
  fire('error')
  const count = wrapper.emitted('snapshot')?.length
  media.video.currentTime = 0
  fire('loadedmetadata')
  fire('timeupdate')
  fire('pause')
  expect(wrapper.emitted('ready')).toHaveLength(1)
  expect(wrapper.emitted('snapshot')).toHaveLength(count!)
  expect(wrapper.vm.capture()?.positionMs).toBe(300000)
  wrapper.unmount()
})

it('keeps quality replacement resets out of history until the replacement seek settles', () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, { props })
  fire('loadedmetadata')
  media.video.currentTime = 300
  fire('timeupdate')
  fire('emptied')
  media.video.currentTime = 0
  fire('loadstart')
  fire('pause')
  fire('loadedmetadata')
  fire('timeupdate')
  expect(wrapper.vm.capture()?.positionMs).toBe(300000)
  expect(wrapper.emitted('snapshot')?.at(-1)?.[0]).toMatchObject({ positionMs: 300000 })

  // Artplayer's later metadata listener restores the position on the new source.
  media.video.currentTime = 300
  media.video.currentSrc = '/smooth.mp4'
  fire('seeked')
  expect(wrapper.vm.capture()).toMatchObject({ positionMs: 300000, initialized: true })
  wrapper.unmount()
})

it.each(['inactive', 'hidden'] as const)(
  'pauses a late quality-switch playing event after the preview becomes %s',
  async (state) => {
    const media = mediaPlayer()
    createPlayer.mockReturnValue(media)
    const wrapper = mount(ProgrammeVideoPlayer, { props })
    fire('loadedmetadata')
    media.video.currentTime = 300
    media.video.paused = false
    fire('playing')
    fire('emptied')
    if (state === 'inactive') {
      await wrapper.setProps({ active: false })
    } else {
      vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
      document.dispatchEvent(new Event('visibilitychange'))
    }

    const pauseCount = media.pause.mock.calls.length
    fire('playing')
    expect(media.pause.mock.calls.length).toBe(pauseCount + 1)
    wrapper.unmount()
    vi.restoreAllMocks()
  },
)

it('settles a zero-position quality replacement on canplay when no seek event is needed', async () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, {
    props: {
      ...props,
      variants: [
        { quality: 'standard', url: props.url },
        { quality: 'smooth', url: '/smooth.mp4' },
      ],
    },
  })
  fire('loadedmetadata')
  fire('loadstart')
  media.video.currentSrc = '/smooth.mp4'
  fire('loadedmetadata')
  expect(wrapper.vm.capture()?.quality).toBe('standard')
  fire('canplay')
  await Promise.resolve()
  expect(wrapper.vm.capture()).toMatchObject({ quality: 'smooth', initialized: true })
  wrapper.unmount()
})

it('does not revive a revoked quality-switch play when visibility returns before it settles', () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  const wrapper = mount(ProgrammeVideoPlayer, { props })
  fire('loadedmetadata')
  media.video.paused = false
  fire('playing')
  fire('emptied')
  wrapper.vm.pause()
  fire('loadedmetadata')
  fire('seeked')
  const pauseCount = media.pause.mock.calls.length
  fire('playing')
  expect(media.pause.mock.calls.length).toBe(pauseCount + 1)

  // A later explicit foreground play remains available.
  fire('playing')
  expect(media.pause.mock.calls.length).toBe(pauseCount + 1)
  wrapper.unmount()
})

it('gates the synchronous quality boundary before a reset pause and revokes resume after seeked', async () => {
  const media = mediaPlayer()
  createPlayer.mockReturnValue(media)
  let complete!: () => void
  media.switchQuality.mockImplementation(() => new Promise<void>((resolve) => (complete = resolve)))
  const wrapper = mount(ProgrammeVideoPlayer, {
    props: {
      ...props,
      variants: [
        { quality: 'standard', url: props.url },
        { quality: 'smooth', url: '/smooth.mp4' },
      ],
    },
  })
  fire('loadedmetadata')
  media.video.currentTime = 300
  media.video.paused = false
  fire('playing')
  const select = media.controls.update.mock.calls.at(-1)?.[0].onSelect
  const switching = select({ url: '/smooth.mp4', html: 'Smooth' })
  media.video.paused = true
  media.video.currentTime = 0
  fire('pause')
  expect(wrapper.vm.capture()).toMatchObject({ positionMs: 300000, playing: true })
  fire('emptied')
  fire('loadedmetadata')
  media.video.currentTime = 300
  fire('seeked')
  const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true)
  document.dispatchEvent(new Event('visibilitychange'))
  hidden.mockReturnValue(false)
  document.dispatchEvent(new Event('visibilitychange'))
  const pauseCount = media.pause.mock.calls.length
  fire('canplay')
  media.video.paused = false
  fire('playing')
  expect(media.pause.mock.calls.length).toBe(pauseCount + 1)
  complete()
  await switching
  wrapper.unmount()
  vi.restoreAllMocks()
})
