// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { defineComponent, nextTick, ref } from 'vue'
import { NModal } from 'naive-ui'

import ProgrammePreviewDialog from './ProgrammePreviewDialog.vue'
import ProgrammeVideoPlayer from './ProgrammeVideoPlayer.vue'

import type { VueWrapper } from '@vue/test-utils'
import type { Ref } from 'vue'
import type { ProgrammeContent } from '../types'

const { pause, destroy } = vi.hoisted(() => ({ pause: vi.fn(), destroy: vi.fn() }))

vi.mock('artplayer', () => ({
  default: class {
    pause = pause
    destroy = destroy
    on = vi.fn()
  },
}))

const episode: ProgrammeContent = {
  id: '1',
  title: 'Programme preview',
  cover: null,
  video: 'https://fscgc.scgchc.com/episode.mp4',
  smoothVideo: null,
  publishedAt: null,
}
let wrapper: VueWrapper
let content: Ref<ProgrammeContent | null>

// Keep the leave transition pending; happy-dom does not run the browser's CSS animation.
const pendingModal = {
  props: { show: Boolean, title: String },
  emits: ['update:show', 'after-leave'],
  template: '<section><h2>{{ title }}</h2><slot /></section>',
}

beforeEach(async () => {
  vi.clearAllMocks()
  content = ref(episode)
  wrapper = mount(
    defineComponent({
      components: { ProgrammePreviewDialog },
      setup: () => ({ content }),
      template: '<ProgrammePreviewDialog v-model="content" quality="standard" />',
    }),
    { global: { stubs: { NModal: pendingModal } } },
  )
  await flushPromises()
})

afterEach(() => wrapper.unmount())

describe('programme preview closing transition', () => {
  it('keeps the title and player until the leave animation finishes', async () => {
    const modal = wrapper.findComponent(NModal)
    expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(true)
    modal.vm.$emit('update:show', false)
    await nextTick()

    expect(modal.props('show')).toBe(false)
    expect(modal.props('title')).toBe('Programme preview')
    expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(true)
    expect(pause).toHaveBeenCalledOnce()
    expect(destroy).not.toHaveBeenCalled()

    modal.vm.$emit('after-leave')
    await nextTick()

    expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(false)
    expect(destroy).toHaveBeenCalledOnce()
  })

  it('also preserves the closing layout when the parent clears the preview', async () => {
    content.value = null
    await nextTick()

    expect(wrapper.findComponent(NModal).props('show')).toBe(false)
    expect(wrapper.findComponent(NModal).props('title')).toBe('Programme preview')
    expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(true)
    expect(pause).toHaveBeenCalledOnce()
    expect(destroy).not.toHaveBeenCalled()
  })

  it('keeps a newly opened preview if an earlier leave callback arrives', async () => {
    const modal = wrapper.findComponent(NModal)
    modal.vm.$emit('update:show', false)
    await nextTick()
    content.value = { ...episode, id: '2', title: 'Another episode' }
    await nextTick()
    modal.vm.$emit('after-leave')
    await nextTick()

    expect(modal.props('show')).toBe(true)
    expect(modal.props('title')).toBe('Another episode')
    expect(wrapper.findComponent(ProgrammeVideoPlayer).attributes('aria-label')).toContain(
      'Another episode',
    )
  })
})
