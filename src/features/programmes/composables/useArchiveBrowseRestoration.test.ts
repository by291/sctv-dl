// @vitest-environment happy-dom

import { afterEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { h, KeepAlive, ref, shallowRef } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'

import { useArchiveBrowseRestoration } from '@/features/programmes/composables/useArchiveBrowseRestoration'

import type { ArchiveBrowseState } from '@shared/contracts/programme-cache'

const wrappers: Array<ReturnType<typeof mount>> = []
afterEach(() => {
  wrappers.splice(0).forEach((wrapper) => wrapper.unmount())
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
})

async function fixture() {
  const frames: FrameRequestCallback[] = []
  vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback) => frames.push(callback))
  vi.stubGlobal('cancelAnimationFrame', vi.fn())
  const scroll = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  vi.spyOn(document.documentElement, 'scrollHeight', 'get').mockReturnValue(2000)
  vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(600)
  const offset = vi.spyOn(window, 'scrollY', 'get').mockReturnValue(100)
  const active = ref(true)
  const programmeId = ref('1')
  const datesLoaded = ref(false)
  const contentsLoaded = ref(false)
  const selectedDateId = ref('10')
  const selectedDate = ref<string | null>('2026-10-01')
  const saved = shallowRef<ArchiveBrowseState | null>({
    programmeId: '1',
    dateId: '10',
    date: '2026-10-01',
    sort: 'desc',
    scrollY: 700,
    visitedAt: '2026-10-17T00:00:00Z',
  })
  const save = vi.fn().mockResolvedValue(undefined)
  const browse = {
    ready: Promise.resolve(),
    saved,
    warning: ref(''),
    save,
    dispose: vi.fn(),
  }
  const archive = {
    setup() {
      useArchiveBrowseRestoration({
        programmeId,
        browse,
        datesLoaded,
        contentsLoaded,
        selectedDateId,
        selectedDate,
      })

      return () => h('div', 'Archive')
    },
  }
  const other = { render: () => h('div', 'Other tab') }
  const workspace = {
    setup: () => () => h(KeepAlive, () => h(active.value ? archive : other)),
  }
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: workspace }],
  })
  await router.push('/')
  const wrapper = mount(RouterView, { global: { plugins: [router] } })
  wrappers.push(wrapper)
  await flushPromises()

  return {
    active,
    programmeId,
    datesLoaded,
    contentsLoaded,
    save,
    scroll,
    offset,
    runFrames() {
      frames.splice(0).forEach((callback) => callback(0))
    },
  }
}

it('keeps the saved offset during hydration until matching content renders', async () => {
  const owner = await fixture()
  owner.datesLoaded.value = true
  await flushPromises()
  expect(owner.save).toHaveBeenLastCalledWith(expect.objectContaining({ scrollY: 700 }))
  expect(owner.scroll).not.toHaveBeenCalled()

  owner.contentsLoaded.value = true
  await flushPromises()
  owner.runFrames()
  expect(owner.scroll).toHaveBeenCalledWith({ left: 0, top: 700, behavior: 'instant' })
})

it('keeps a returning tab at its live offset when content finishes while hidden', async () => {
  const owner = await fixture()
  owner.datesLoaded.value = true
  await flushPromises()
  owner.active.value = false
  await flushPromises()
  owner.save.mockClear()

  owner.contentsLoaded.value = true
  await flushPromises()
  owner.runFrames()
  expect(owner.scroll).not.toHaveBeenCalled()
  expect(owner.save).not.toHaveBeenCalled()

  owner.active.value = true
  await flushPromises()
  owner.offset.mockReturnValue(320)
  window.dispatchEvent(new Event('pagehide'))
  await flushPromises()
  expect(owner.scroll).not.toHaveBeenCalled()
  expect(owner.save).toHaveBeenLastCalledWith(expect.objectContaining({ scrollY: 320 }))
})

it('rejects a queued restoration owned by a previous programme', async () => {
  const owner = await fixture()
  owner.datesLoaded.value = true
  owner.contentsLoaded.value = true
  await flushPromises()

  owner.programmeId.value = '2'
  owner.datesLoaded.value = false
  owner.contentsLoaded.value = false
  await flushPromises()
  owner.scroll.mockClear()
  owner.save.mockClear()
  owner.runFrames()
  expect(owner.scroll).not.toHaveBeenCalled()
  expect(owner.save).not.toHaveBeenCalled()
})
