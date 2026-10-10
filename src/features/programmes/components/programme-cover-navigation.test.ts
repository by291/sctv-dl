// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { NMessageProvider } from 'naive-ui'

import AppLayout from '../../../layouts/AppLayout.vue'
import LibraryView from '../views/LibraryView.vue'
import ProgrammeView from '../views/ProgrammeView.vue'
import { api } from '../api'
import { useProgrammeStore } from '../store'
import { useSettingsStore } from '../../settings/store'

import type { VueWrapper } from '@vue/test-utils'

vi.mock('../api', () => ({
  api: { dates: vi.fn(), contents: vi.fn(), programmes: vi.fn() },
}))

let wrapper: VueWrapper
let router: ReturnType<typeof createRouter>
let sources: string[]
let destinationRendered: boolean
let startTransition: ReturnType<typeof vi.fn>
const originalTransition = Object.getOwnPropertyDescriptor(document, 'startViewTransition')

beforeEach(async () => {
  localStorage.clear()
  sources = []
  destinationRendered = false
  vi.mocked(api.dates).mockResolvedValue([])
  startTransition = vi.fn((update: () => Promise<void>) => {
    sources = Array.from(document.querySelectorAll<HTMLElement>('.cover-image'))
      .filter((cover) => cover.style.viewTransitionName === 'programme-cover')
      .map((cover) => cover.className)
    const updateCallbackDone = Promise.resolve()
      .then(update)
      .then(() => {
        destinationRendered = Boolean(document.querySelector('.detail-cover'))
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
  const catalogue = useProgrammeStore()
  catalogue.programmes = [{ id: '1', name: 'Programme', cover: null }]
  catalogue.updatedAt = new Date()
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: LibraryView },
      { path: '/programmes/:id', component: async () => ProgrammeView, props: true },
      { path: '/settings', component: LibraryView },
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
  useProgrammeStore().$dispose()
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
    startTransition.mockImplementation(capture!)
    await wrapper.get('.featured-visual').trigger('click')
    await flushPromises()

    expect(startTransition).toHaveBeenCalledTimes(2)
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
})
