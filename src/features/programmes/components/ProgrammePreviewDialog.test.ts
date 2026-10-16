// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { computed, defineComponent, nextTick, ref } from 'vue'
import { NModal } from 'naive-ui'

import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

import { platformKey } from '@/shared/platform/usePlatform'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'

import type { VueWrapper } from '@vue/test-utils'
import type { Ref } from 'vue'
import type { ProgrammeContent } from '@/features/programmes/model/programme'

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
const open = vi.fn()
const close = vi.fn().mockResolvedValue(undefined)
let wrapper: VueWrapper
let content: Ref<ProgrammeContent | null>

// Vue Test Utils stubs CSS transitions, so after-leave is emitted explicitly below.

beforeEach(async () => {
  vi.clearAllMocks()
  open.mockImplementation(async (request) => ({
    id: request.contentId,
    selectedQuality: 'standard',
    sources: [{ quality: 'standard', url: '/fixture.mp4' }],
  }))
  const platform = createPlatformFixture()
  platform.playback = { open, close }
  content = ref(episode)
  wrapper = mount(
    defineComponent({
      components: { ProgrammePreviewDialog },
      setup: () => ({
        content,
        reference: computed(() =>
          content.value ? { programmeId: '1', dateId: '2', contentId: content.value.id } : null,
        ),
      }),
      template:
        '<ProgrammePreviewDialog v-model="content" :reference="reference" quality="standard" />',
    }),
    { global: { provide: { [platformKey as symbol]: platform } } },
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
    expect(close).toHaveBeenCalledWith('1')
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
    await flushPromises()
    modal.vm.$emit('after-leave')
    await nextTick()

    expect(modal.props('show')).toBe(true)
    expect(modal.props('title')).toBe('Another episode')
    expect(wrapper.findComponent(ProgrammeVideoPlayer).attributes('aria-label')).toContain(
      'Another episode',
    )
  })
})

it('releases a late open after cancellation without displaying it', async () => {
  let resolve!: (value: unknown) => void
  open.mockImplementationOnce(
    () =>
      new Promise((done) => {
        resolve = done
      }),
  )
  content.value = { ...episode, id: '2' }
  await nextTick()
  expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(false)
  content.value = null
  await nextTick()
  resolve({
    id: 'late',
    selectedQuality: 'standard',
    sources: [{ quality: 'standard', url: '/late.mp4' }],
  })
  await flushPromises()
  expect(close).toHaveBeenCalledWith('late')
  expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(false)
})

it('shows backend preparation errors and retries the domain reference', async () => {
  open.mockRejectedValueOnce(new Error('Video service unavailable'))
  content.value = { ...episode, id: '2' }
  await flushPromises()
  expect(document.querySelector('[role="alert"]')?.textContent).toContain(
    'Video service unavailable',
  )
  document.querySelector<HTMLButtonElement>('.preview-retry')!.click()
  await flushPromises()
  expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(true)
  expect(open.mock.calls.at(-1)?.[0]).toEqual({
    programmeId: '1',
    dateId: '2',
    contentId: '2',
    quality: 'standard',
  })
})
