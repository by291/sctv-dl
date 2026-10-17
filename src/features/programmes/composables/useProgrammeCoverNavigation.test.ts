// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider } from 'naive-ui'

import AppLayout from '@/layouts/AppLayout.vue'
import ProgrammeLibraryView from '@/features/programmes/views/ProgrammeLibraryView.vue'
import ProgrammeArchiveView from '@/features/programmes/views/ProgrammeArchiveView.vue'
import type { ProgrammeApi } from '@/shared/platform/ports'
import { useProgrammeCatalogueStore } from '@/features/programmes/stores/useProgrammeCatalogueStore'
import { useSettingsStore } from '@/features/settings/stores/useSettingsStore'

import type { VueWrapper } from '@vue/test-utils'

const programmeApi = vi.hoisted(() => ({
  dates: vi.fn<ProgrammeApi['dates']>(),
  contents: vi.fn<ProgrammeApi['contents']>(),
  programmes: vi.fn<ProgrammeApi['programmes']>(),
}))

vi.mock('@/shared/platform/usePlatform', async () => {
  const { createPlatformFixture } = await import('@/shared/platform/platform.test-support')
  const platform = createPlatformFixture()

  return { usePlatform: () => ({ ...platform, programmes: programmeApi }) }
})

let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>
let sources: string[]
let destinationRendered: boolean
let startTransition: ReturnType<typeof vi.fn>
let captures: { before: string[]; after: string[]; scroll: number }[]
const originalTransition = Object.getOwnPropertyDescriptor(document, 'startViewTransition')

function namedCovers(): string[] {
  return Array.from(document.querySelectorAll<HTMLElement>('.cover-image'))
    .filter((cover) => cover.style.viewTransitionName === 'programme-cover')
    .map((cover) => cover.className)
}

beforeEach(async () => {
  localStorage.clear()
  sources = []
  captures = []
  destinationRendered = false
  programmeApi.dates.mockReset().mockResolvedValue([])
  programmeApi.contents.mockReset().mockResolvedValue([])
  programmeApi.programmes
    .mockReset()
    .mockResolvedValue([{ id: '1', name: 'Programme', cover: null }])
  startTransition = vi.fn((update: () => Promise<void>) => {
    sources = namedCovers()
    const before = document.querySelector('.detail-cover') ? ['detail-cover'] : sources
    const updateCallbackDone = Promise.resolve()
      .then(update)
      .then(() => {
        destinationRendered = Boolean(document.querySelector('.detail-cover'))
        captures.push({
          before,
          after: namedCovers(),
          scroll: document.getElementById('workspace-scroll')?.scrollTop ?? 0,
        })
      })

    return {
      ready: updateCallbackDone,
      updateCallbackDone,
      finished: updateCallbackDone,
      skipTransition: vi.fn(),
    }
  })
  Object.defineProperty(document, 'startViewTransition', {
    configurable: true,
    writable: true,
    value: startTransition,
  })
  vi.spyOn(window, 'matchMedia').mockReturnValue({ matches: false } as MediaQueryList)

  const pinia = createPinia()
  setActivePinia(pinia)
  const catalogue = useProgrammeCatalogueStore()
  catalogue.programmes = [{ id: '1', name: 'Programme', cover: null }]
  catalogue.updatedAt = new Date()
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: ProgrammeLibraryView },
      { path: '/programmes/:id', component: async () => ProgrammeArchiveView, props: true },
      { path: '/settings', component: { template: '<h1>Settings</h1>' } },
      { path: '/history', component: { template: '<h1>History</h1>' } },
    ],
  })
  await router.push('/')
  await router.isReady()
  wrapper = mount(
    {
      components: { NMessageProvider, AppLayout },
      template: '<NMessageProvider><AppLayout /></NMessageProvider>',
    },
    { attachTo: document.body, global: { plugins: [pinia, router], stubs: { transition: false } } },
  )
  await flushPromises()
})

afterEach(async () => {
  wrapper.unmount()
  await flushPromises()
  useProgrammeCatalogueStore().$dispose()
  useSettingsStore().$dispose()
  vi.restoreAllMocks()

  if (originalTransition) {
    Object.defineProperty(document, 'startViewTransition', originalTransition)
  } else {
    Reflect.deleteProperty(document, 'startViewTransition')
  }
})

describe('programme cover navigation', () => {
  it.each([
    { link: '.programme-cover', cover: 'programme-image' },
    { link: '.programme-caption', cover: 'programme-image' },
    { link: '.featured-visual', cover: 'featured-image' },
    { link: '.feature-link', cover: 'featured-image' },
  ])('shares only the associated cover when activating $link', async ({ link, cover }) => {
    await wrapper.get(link).trigger('click')
    await flushPromises()

    expect(startTransition).toHaveBeenCalledOnce()
    expect(sources).toHaveLength(1)
    expect(sources[0]).toContain(cover)
    expect(destinationRendered).toBe(true)
    expect(router.currentRoute.value.path).toBe('/programmes/1')
    expect(wrapper.get('.detail-title').text()).toBe('Programme')
  })

  it.each([
    { link: '.programme-cover', cover: 'programme-image', history: false },
    { link: '.programme-cover', cover: 'programme-image', history: true },
    { link: '.featured-visual', cover: 'featured-image', history: false },
    { link: '.featured-visual', cover: 'featured-image', history: true },
  ])('returns to the original $cover (history: $history)', async ({ link, cover, history }) => {
    const originalCover = wrapper.get(`.${cover}`).element
    const workspace = wrapper.get<HTMLElement>('#workspace-scroll').element
    workspace.scrollTo({ top: 480, left: 0 })
    await wrapper.get(link).trigger('click')
    await flushPromises()
    workspace.scrollTo({ top: 0, left: 0 })

    if (history) {
      router.back()
    } else {
      await wrapper.get('.back-link').trigger('click')
    }

    await flushPromises()
    expect(router.currentRoute.value.path).toBe('/')
    expect(startTransition).toHaveBeenCalledTimes(2)
    expect(captures[1]?.before).toEqual(['detail-cover'])
    expect(captures[1]?.after).toHaveLength(1)
    expect(captures[1]?.after[0]).toContain(cover)
    expect(captures[1]?.scroll).toBe(480)
    expect(wrapper.get(`.${cover}`).element).toBe(originalCover)
    expect(namedCovers()).toEqual([])
  })

  it('retries a blocked return without losing the original cover', async () => {
    await wrapper.get('.featured-visual').trigger('click')
    await flushPromises()
    const removeGuard = router.beforeResolve(() => false)
    await wrapper.get('.back-link').trigger('click')
    await flushPromises()
    expect(router.currentRoute.value.path).toBe('/programmes/1')

    removeGuard()
    await wrapper.get('.back-link').trigger('click')
    await flushPromises()
    expect(router.currentRoute.value.path).toBe('/')
    expect(startTransition).toHaveBeenCalledTimes(3)
    expect(captures.at(-1)?.after[0]).toContain('featured-image')
    expect(namedCovers()).toEqual([])
  })

  it.each([
    { link: '.programme-cover', cover: 'programme-image', history: false },
    { link: '.featured-visual', cover: 'featured-image', history: false },
    { link: '.programme-cover', cover: 'programme-image', history: true },
  ])(
    'retains the $cover return animation across tab switches (history: $history)',
    async ({ link, cover, history }) => {
      const original = wrapper.get(`.${cover}`).element
      wrapper.get<HTMLElement>('#workspace-scroll').element.scrollTo({ top: 480 })
      await wrapper.get(link).trigger('click')
      await flushPromises()
      await router.push('/settings')
      await flushPromises()

      if (history) {
        router.back()
      } else {
        await wrapper.get('.nav-link').trigger('click')
      }

      await flushPromises()
      expect(router.currentRoute.value.path).toBe('/programmes/1')
      expect(startTransition).toHaveBeenCalledOnce()

      if (history) {
        router.back()
      } else {
        await wrapper.get('.back-link').trigger('click')
      }

      await flushPromises()

      expect(router.currentRoute.value.path).toBe('/')
      expect(startTransition).toHaveBeenCalledTimes(2)
      expect(captures[1]?.before).toEqual(['detail-cover'])
      expect(captures[1]?.after).toHaveLength(1)
      expect(captures[1]?.after[0]).toContain(cover)
      expect(captures[1]?.scroll).toBe(480)
      expect(wrapper.get(`.${cover}`).element).toBe(original)
      expect(namedCovers()).toEqual([])
    },
  )

  it('releases the old cover association when a home link replaces the hidden detail', async () => {
    await wrapper.get('.programme-cover').trigger('click')
    await flushPromises()
    await router.push('/settings')
    await flushPromises()
    await wrapper.get('.brand').trigger('click')
    await flushPromises()
    await vi.waitFor(() => expect(wrapper.find('.programme-cover').exists()).toBe(true))

    // A later direct entry has no animated source and must not reuse the disposed detail's hook.
    await router.push('/programmes/1')
    await vi.waitFor(() => expect(wrapper.find('.detail-cover').exists()).toBe(true))
    await router.push('/')
    await vi.waitFor(() => expect(wrapper.find('.programme-cover').exists()).toBe(true))

    expect(startTransition).toHaveBeenCalledOnce()
    expect(namedCovers()).toEqual([])
  })

  it.each([
    { ctrlKey: true },
    { metaKey: true },
    { shiftKey: true },
    { altKey: true },
    { button: 1 },
  ])('preserves modified link activation %j', async (modifiers) => {
    await wrapper.get('.programme-cover').trigger('click', modifiers)
    await flushPromises()

    expect(startTransition).not.toHaveBeenCalled()
    expect(router.currentRoute.value.path).toBe('/')
    expect(wrapper.get('.programme-cover').attributes('href')).toBe('/programmes/1')
  })

  it.each(['unsupported', 'reduced motion'])('navigates normally with %s', async (condition) => {
    if (condition === 'unsupported') {
      Reflect.deleteProperty(document, 'startViewTransition')
    } else {
      vi.mocked(window.matchMedia).mockReturnValue({ matches: true } as MediaQueryList)
    }

    await wrapper.get('.featured-visual').trigger('click')
    await vi.waitFor(() => expect(wrapper.find('.detail-cover').exists()).toBe(true))

    expect(startTransition).not.toHaveBeenCalled()
    expect(router.currentRoute.value.path).toBe('/programmes/1')
  })

  it('clears the source name after an aborted route and allows a subsequent transition', async () => {
    const removeGuard = router.beforeEach(() => false)
    await wrapper.get('.programme-cover').trigger('click')
    await flushPromises()

    expect(startTransition).toHaveBeenCalledOnce()
    expect(router.currentRoute.value.path).toBe('/')
    expect(wrapper.get('.programme-image').element.getAttribute('style')).not.toContain(
      'programme-cover',
    )
    removeGuard()
    await wrapper.get('.featured-visual').trigger('click')
    await flushPromises()

    expect(startTransition).toHaveBeenCalledTimes(2)
    expect(destinationRendered).toBe(true)
    expect(sources[0]).toContain('featured-image')
  })

  it('still navigates if the native API throws before accepting the callback', async () => {
    startTransition.mockImplementation(() => {
      throw new Error('Capture unavailable')
    })
    await wrapper.get('.programme-cover').trigger('click')
    await vi.waitFor(() => expect(wrapper.find('.detail-cover').exists()).toBe(true))

    expect(router.currentRoute.value.path).toBe('/programmes/1')
  })

  it('finishes navigation and restores subsequent transitions after a skipped capture', async () => {
    const capture = startTransition.getMockImplementation()
    startTransition.mockImplementation((update: () => Promise<void>) => {
      const updateCallbackDone = Promise.resolve().then(update)

      return {
        ready: updateCallbackDone.then(() => {
          throw new Error('Capture skipped')
        }),
        updateCallbackDone,
        finished: updateCallbackDone,
        skipTransition: vi.fn(),
      }
    })
    await wrapper.get('.programme-cover').trigger('click')
    await flushPromises()
    expect(wrapper.find('.detail-cover').exists()).toBe(true)

    await router.push('/')
    await vi.waitFor(() => expect(wrapper.find('.featured-visual').exists()).toBe(true))
    await flushPromises()
    startTransition.mockImplementation(capture!)
    await wrapper.get('.featured-visual').trigger('click')
    await flushPromises()

    expect(startTransition).toHaveBeenCalledTimes(3)
    expect(destinationRendered).toBe(true)
  })

  it('supports keyboard-generated link clicks', async () => {
    await wrapper.get('.feature-link').trigger('click', { detail: 0 })
    await flushPromises()

    expect(startTransition).toHaveBeenCalledOnce()
    expect(sources[0]).toContain('featured-image')
    expect(destinationRendered).toBe(true)
  })

  it.each([false, true])(
    'does not overwrite a newer navigation (pending guard: %s)',
    async (pending) => {
      let runUpdate: () => Promise<void> = async () => {}

      const skipTransition = vi.fn()
      startTransition.mockImplementation((update: () => Promise<void>) => {
        const updateCallbackDone = new Promise<void>((resolve, reject) => {
          runUpdate = async () => {
            try {
              await update()
              resolve()
            } catch (error) {
              reject(error)
            }
          }
        })

        return {
          ready: updateCallbackDone,
          updateCallbackDone,
          finished: updateCallbackDone,
          skipTransition,
        }
      })
      await wrapper.get('.programme-cover').trigger('click')
      await flushPromises()

      let releaseGuard: () => void = () => {}

      const guard = new Promise<void>((resolve) => {
        releaseGuard = resolve
      })
      router.beforeResolve(async (to) => {
        if (pending && to.path === '/settings') {
          await guard
        }
      })
      const navigation = router.push('/settings')
      await flushPromises()
      await runUpdate()
      await flushPromises()
      releaseGuard()
      await navigation

      expect(router.currentRoute.value.path).toBe('/settings')
      expect(skipTransition).toHaveBeenCalledOnce()
    },
  )

  it.each(['unsupported', 'reduced motion', 'capture failure'])(
    'returns normally with %s after an animated entry',
    async (condition) => {
      await wrapper.get('.programme-cover').trigger('click')
      await flushPromises()

      if (condition === 'unsupported') {
        Reflect.deleteProperty(document, 'startViewTransition')
      } else if (condition === 'reduced motion') {
        vi.mocked(window.matchMedia).mockReturnValue({ matches: true } as MediaQueryList)
      } else {
        startTransition.mockImplementation(() => {
          throw new Error('Capture unavailable')
        })
      }

      await wrapper.get('.back-link').trigger('click')
      await vi.waitFor(() => expect(wrapper.find('.programme-cover').exists()).toBe(true))
      await flushPromises()
      expect(router.currentRoute.value.path).toBe('/')
      expect(namedCovers()).toEqual([])
    },
  )

  it.each([false, true])(
    'does not replace a newer navigation with a deferred return (pending guard: %s)',
    async (pending) => {
      await wrapper.get('.featured-visual').trigger('click')
      await flushPromises()
      let runUpdate: () => Promise<void> = async () => {}

      const skipTransition = vi.fn()
      startTransition.mockImplementation((update: () => Promise<void>) => {
        const updateCallbackDone = new Promise<void>((resolve, reject) => {
          runUpdate = async () => {
            try {
              await update()
              resolve()
            } catch (error) {
              reject(error)
            }
          }
        })

        return {
          ready: updateCallbackDone,
          updateCallbackDone,
          finished: updateCallbackDone,
          skipTransition,
        }
      })
      const returning = router.push('/')
      await flushPromises()
      expect(startTransition).toHaveBeenCalledTimes(2)
      expect(router.currentRoute.value.path).toBe('/programmes/1')
      let releaseGuard: () => void = () => {}

      const guard = new Promise<void>((resolve) => {
        releaseGuard = resolve
      })
      router.beforeResolve(async (to) => {
        if (pending && to.path === '/settings') {
          await guard
        }
      })
      const newer = router.push('/settings')
      await flushPromises()
      await runUpdate()
      releaseGuard()
      await Promise.all([returning, newer])
      await flushPromises()

      expect(router.currentRoute.value.path).toBe('/settings')
      expect(skipTransition).toHaveBeenCalledOnce()
      expect(namedCovers()).toEqual([])
    },
  )

  it('uses ordinary navigation if the original source has disappeared', async () => {
    await wrapper.get('.programme-cover').trigger('click')
    await flushPromises()
    useProgrammeCatalogueStore().programmes = []
    await flushPromises()
    await wrapper.get('.back-link').trigger('click')
    await vi.waitFor(() => expect(wrapper.find('.library-view').exists()).toBe(true))
    await flushPromises()

    expect(router.currentRoute.value.path).toBe('/')
    expect(startTransition).toHaveBeenCalledOnce()
    expect(namedCovers()).toEqual([])
  })

  it.each([
    { link: '.programme-cover', replacement: [] },
    { link: '.featured-visual', replacement: [{ id: '2', name: 'Other', cover: null }] },
  ])('skips a deferred return when $link changes or unmounts', async ({ link, replacement }) => {
    await wrapper.get(link).trigger('click')
    await flushPromises()
    let runUpdate: () => Promise<void> = async () => {}

    const skipTransition = vi.fn()
    startTransition.mockImplementation((update: () => Promise<void>) => {
      const updateCallbackDone = new Promise<void>((resolve, reject) => {
        runUpdate = async () => {
          try {
            await update()
            resolve()
          } catch (error) {
            reject(error)
          }
        }
      })

      return {
        ready: updateCallbackDone,
        updateCallbackDone,
        finished: updateCallbackDone,
        skipTransition,
      }
    })
    const returning = router.push('/')
    await flushPromises()
    useProgrammeCatalogueStore().programmes = replacement
    await flushPromises()
    await runUpdate()
    await returning
    await flushPromises()

    expect(router.currentRoute.value.path).toBe('/')
    expect(skipTransition).toHaveBeenCalledOnce()
    expect(namedCovers()).toEqual([])
  })
})
