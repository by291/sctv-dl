// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { computed, defineComponent, nextTick, ref } from 'vue'
import { createPinia } from 'pinia'
import { NModal } from 'naive-ui'

import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'
import ProgrammeVideoPlayer from '@/features/programmes/components/ProgrammeVideoPlayer.vue'

import { platformKey } from '@/shared/platform/usePlatform'
import {
  createPlatformFixture,
  createNativeDownloadFixture,
} from '@/shared/platform/platform.test-support'

import type { VueWrapper } from '@vue/test-utils'
import type { PreviewInput } from '@/features/programmes/model/playback-state'
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
const openLocal = vi.fn()
const open = vi.fn()
const close = vi.fn().mockResolvedValue(undefined)
let wrapper: VueWrapper
let content: Ref<ProgrammeContent | null>
let input: Ref<PreviewInput | null>
const record = vi.fn().mockResolvedValue({ accepted: true, persisted: true })
const end = vi.fn().mockResolvedValue(undefined)
const begin = vi.fn()

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
  platform.downloads = { ...createNativeDownloadFixture(), openPlayback: openLocal }
  platform.history = {
    begin,
    record,
    end,
    list: vi.fn(),
    remove: vi.fn(),
    clear: vi.fn(),
    subscribe: vi.fn(),
    flush: vi.fn(),
    getWriteRevision: () => 0,
  }
  begin.mockResolvedValue({ id: 'history-1', entry: null })
  content = ref(episode)
  input = ref(null)
  wrapper = mount(
    defineComponent({
      components: { ProgrammePreviewDialog },
      setup: () => ({
        content,
        input,
        reference: computed(() =>
          content.value ? { programmeId: '1', dateId: '2', contentId: content.value.id } : null,
        ),
      }),
      template:
        '<ProgrammePreviewDialog v-model="content" :reference="reference" :input="input" quality="standard" />',
    }),
    {
      global: {
        plugins: [createPinia()],
        provide: { [platformKey as symbol]: platform },
      },
    },
  )
  await flushPromises()
})

afterEach(() => wrapper.unmount())

function previewTitle(): string {
  // Render the public header slot even after the transition stub hides the modal DOM.
  const header = mount({ render: () => wrapper.getComponent(NModal).vm.$slots.header?.() })
  const title = header.get('.preview-title').text()
  header.unmount()

  return title
}

describe('programme preview closing transition', () => {
  it('keeps the title and player until the leave animation finishes', async () => {
    const modal = wrapper.findComponent(NModal)
    expect(wrapper.findComponent(ProgrammeVideoPlayer).exists()).toBe(true)
    modal.vm.$emit('update:show', false)
    await nextTick()

    expect(modal.props('show')).toBe(false)
    expect(previewTitle()).toBe('Programme preview')
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
    expect(previewTitle()).toBe('Programme preview')
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
    expect(previewTitle()).toBe('Another episode')
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

const pinned: PreviewInput = {
  kind: 'online',
  content: episode,
  metadata: {
    content: { programmeId: '1', dateId: '2', contentId: '1' },
    programmeName: 'News',
    broadcastDate: '2026-10-17',
    title: episode.title,
    cover: null,
  },
}
const usable = {
  positionMs: 300000,
  durationMs: 600000,
  speed: 1.5,
  quality: 'smooth' as const,
  playing: false,
  ended: false,
  initialized: true,
}

it('restores saved history paused and retains the same history session through retry', async () => {
  begin.mockResolvedValue({
    id: 'resume',
    entry: {
      ...pinned.metadata,
      positionMs: 300000,
      durationMs: 600000,
      completed: false,
      viewedAt: '2026-10-17T00:00:00Z',
    },
  })
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  let player = wrapper.findComponent(ProgrammeVideoPlayer)
  expect(player.props('restore')).toEqual({ positionMs: 300000, speed: 1, playing: false })
  player.vm.$emit('snapshot', usable, 'state')
  player.vm.$emit('error')
  await nextTick()
  document.querySelector<HTMLButtonElement>('.preview-retry')!.click()
  await flushPromises()
  player = wrapper.findComponent(ProgrammeVideoPlayer)
  expect(open.mock.calls.at(-1)?.[0].quality).toBe('smooth')
  expect(player.props('restore')).toEqual({ positionMs: 300000, speed: 1.5, playing: false })
  expect(begin).toHaveBeenCalledOnce()
})

it('captures final usable progress before leave and ends history only after leave', async () => {
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  wrapper.findComponent(ProgrammeVideoPlayer).vm.$emit('snapshot', usable, 'state')
  content.value = null
  await flushPromises()
  expect(record).toHaveBeenCalledWith('history-1', expect.objectContaining({ positionMs: 300000 }))
  expect(end).not.toHaveBeenCalled()
  wrapper.findComponent(NModal).vm.$emit('after-leave')
  await flushPromises()
  expect(end).toHaveBeenCalledExactlyOnceWith('history-1')
})

it('revokes playing retry intent after backgrounding during preparation', async () => {
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  const player = wrapper.findComponent(ProgrammeVideoPlayer)
  player.vm.$emit('snapshot', { ...usable, playing: true }, 'state')
  player.vm.$emit('error')
  await nextTick()
  let resolve!: (value: unknown) => void
  open.mockImplementationOnce(
    () =>
      new Promise((done) => {
        resolve = done
      }),
  )
  document.querySelector<HTMLButtonElement>('.preview-retry')!.click()
  await nextTick()
  Object.defineProperty(document, 'hidden', { configurable: true, value: true })
  document.dispatchEvent(new Event('visibilitychange'))
  Object.defineProperty(document, 'hidden', { configurable: true, value: false })
  document.dispatchEvent(new Event('visibilitychange'))
  resolve({
    id: 'retry',
    selectedQuality: 'smooth',
    sources: [{ quality: 'smooth', url: '/retry.mp4' }],
  })
  await flushPromises()
  expect(wrapper.findComponent(ProgrammeVideoPlayer).props('restore')?.playing).toBe(false)
  Reflect.deleteProperty(document, 'hidden')
})

it('keeps pinned content IDs when archive reference changes during an open preview', async () => {
  input.value = pinned
  content.value = { ...episode, id: 'different-archive-id' }
  await flushPromises()
  expect(open.mock.calls.at(-1)?.[0]).toMatchObject(pinned.metadata.content)
  expect(previewTitle()).toBe(pinned.content.title)
})

it('does not overwrite saved progress when media preparation fails before restoration', async () => {
  begin.mockResolvedValue({
    id: 'resume',
    entry: {
      ...pinned.metadata,
      positionMs: 300000,
      durationMs: 600000,
      completed: false,
      viewedAt: '2026-10-17T00:00:00Z',
    },
  })
  open.mockRejectedValueOnce(new Error('Unavailable source'))
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  content.value = null
  await flushPromises()
  wrapper.findComponent(NModal).vm.$emit('after-leave')
  await flushPromises()
  expect(record).not.toHaveBeenCalled()
  expect(end).toHaveBeenCalledWith('resume')
})

it('saves a visibility capture immediately outside the forward-progress throttle', async () => {
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  wrapper.findComponent(ProgrammeVideoPlayer).vm.$emit('snapshot', usable, 'progress')
  await flushPromises()
  wrapper
    .findComponent(ProgrammeVideoPlayer)
    .vm.$emit('snapshot', { ...usable, positionMs: 301000 }, 'progress')
  Object.defineProperty(document, 'hidden', { configurable: true, value: true })
  document.dispatchEvent(new Event('visibilitychange'))
  await flushPromises()
  expect(record.mock.calls.at(-1)?.[1]).toMatchObject({ positionMs: 301000 })
  Reflect.deleteProperty(document, 'hidden')
})

it('closes a late playing retry without releasing the replacement preview', async () => {
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  const player = wrapper.findComponent(ProgrammeVideoPlayer)
  player.vm.$emit('snapshot', { ...usable, playing: true }, 'state')
  player.vm.$emit('error')
  await nextTick()
  let resolve!: (value: unknown) => void
  open.mockImplementationOnce(
    () =>
      new Promise((done) => {
        resolve = done
      }),
  )
  document.querySelector<HTMLButtonElement>('.preview-retry')!.click()
  await nextTick()
  content.value = null
  await nextTick()
  input.value = {
    ...pinned,
    metadata: { ...pinned.metadata, content: { ...pinned.metadata.content, contentId: 'new' } },
    content: { ...episode, id: 'new', title: 'New preview' },
  }
  content.value = input.value.content
  await flushPromises()
  resolve({
    id: 'late-retry',
    selectedQuality: 'smooth',
    sources: [{ quality: 'smooth', url: '/late-retry.mp4' }],
  })
  await flushPromises()
  expect(close).toHaveBeenCalledWith('late-retry')
  expect(close).not.toHaveBeenCalledWith('new')
  expect(wrapper.findComponent(ProgrammeVideoPlayer).props('restore')?.playing).toBe(false)
  expect(previewTitle()).toBe('New preview')
})

it('discloses fallback quality when retry cannot recover the last selected source', async () => {
  input.value = pinned
  content.value = { ...episode }
  await flushPromises()
  const player = wrapper.findComponent(ProgrammeVideoPlayer)
  player.vm.$emit('snapshot', usable, 'state')
  player.vm.$emit('error')
  await nextTick()
  document.querySelector<HTMLButtonElement>('.preview-retry')!.click()
  await flushPromises()
  expect(document.querySelector('.preview-quality-notice')?.textContent).toContain('已使用标准画质')
})

it('captures and releases an off-page preview when KeepAlive deactivates it', async () => {
  wrapper.unmount()
  vi.clearAllMocks()
  const visible = ref(true)
  content.value = episode
  input.value = pinned
  const platform = createPlatformFixture()
  platform.playback = { open, close }
  platform.downloads = { ...createNativeDownloadFixture(), openPlayback: openLocal }
  platform.history = {
    begin,
    record,
    end,
    list: vi.fn(),
    remove: vi.fn(),
    clear: vi.fn(),
    subscribe: vi.fn(),
    flush: vi.fn(),
    getWriteRevision: () => 0,
  }
  wrapper = mount(
    {
      components: { ProgrammePreviewDialog },
      setup: () => ({ visible, content, input, reference: pinned.metadata.content }),
      template:
        '<KeepAlive><ProgrammePreviewDialog v-if="visible" v-model="content" :input="input" :reference="reference" quality="standard" /></KeepAlive>',
    },
    { global: { plugins: [createPinia()], provide: { [platformKey as symbol]: platform } } },
  )
  await flushPromises()
  wrapper.findComponent(ProgrammeVideoPlayer).vm.$emit('snapshot', usable, 'state')
  visible.value = false
  await flushPromises()
  expect(record).toHaveBeenCalledWith('history-1', expect.objectContaining({ positionMs: 300000 }))
  expect(close).toHaveBeenCalledExactlyOnceWith('1')
  expect(end).toHaveBeenCalledExactlyOnceWith('history-1')
})

it('opens a downloaded task locally and never substitutes an online source on failure', async () => {
  open.mockClear()
  openLocal.mockResolvedValueOnce({
    id: 'local-session',
    selectedQuality: 'standard',
    sources: [{ quality: 'standard', url: '/local.mp4' }],
  })
  input.value = { ...pinned, kind: 'download', taskId: 'saved-task' }
  await flushPromises()
  expect(openLocal).toHaveBeenCalledWith('saved-task', expect.any(AbortSignal))
  expect(open).not.toHaveBeenCalled()
  openLocal.mockRejectedValueOnce(new Error('本地文件已丢失'))
  wrapper.findComponent(ProgrammeVideoPlayer).vm.$emit('error')
  await nextTick()
  document.querySelector<HTMLButtonElement>('.preview-retry')!.click()
  await flushPromises()
  expect(document.body.textContent).toContain('本地文件已丢失')
  expect(open).not.toHaveBeenCalled()
})
