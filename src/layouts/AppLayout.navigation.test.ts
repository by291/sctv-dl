// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, disposePinia } from 'pinia'
import { NMessageProvider } from 'naive-ui'

import AppLayout from '@/layouts/AppLayout.vue'
import { createAppRouter } from '@/router'
import {
  createScrollRestoration,
  scrollRestorationKey,
} from '@/shared/navigation/scroll-restoration'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'

afterEach(() => vi.restoreAllMocks())

async function renderPage() {
  await flushPromises()
  await new Promise(requestAnimationFrame)
  await flushPromises()
}

it('coordinates live tab positions, duplicate clicks, and older browser history entries', async () => {
  window.history.replaceState(null, '', '/')
  vi.spyOn(HTMLElement.prototype, 'scrollHeight', 'get').mockReturnValue(3000)
  vi.spyOn(HTMLElement.prototype, 'clientHeight', 'get').mockReturnValue(600)
  const platform = createPlatformFixture()
  platform.programmes.programmes = async () => [{ id: '1', name: 'News', cover: null }]
  const coordinator = createScrollRestoration()
  const router = createAppRouter('web', coordinator)
  const pinia = createPinia()
  const wrapper = mount(
    {
      components: { AppLayout, NMessageProvider },
      template: '<NMessageProvider><AppLayout /></NMessageProvider>',
    },
    {
      attachTo: document.body,
      global: {
        plugins: [pinia, router],
        provide: {
          [platformKey as symbol]: platform,
          [scrollRestorationKey as symbol]: coordinator,
        },
      },
    },
  )
  const scroll = () => wrapper.get<HTMLElement>('#workspace-scroll').element

  try {
    await router.isReady()
    await renderPage()
    await router.push('/programmes/1')
    await renderPage()
    const detail = wrapper.get('.detail-cover').element
    scroll().scrollTo({ top: 500 })
    await router.push('/settings')
    await renderPage()
    await wrapper.get('.nav-link').trigger('click')
    await renderPage()
    expect(scroll().scrollTop).toBe(500)

    scroll().scrollTo({ top: 900 })
    await wrapper.get('.nav-link').trigger('click')
    await renderPage()
    expect(scroll().scrollTop).toBe(900)
    await router.push('/settings')
    await renderPage()

    router.back()
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/programmes/1'))
    await renderPage()
    expect(scroll().scrollTop).toBe(900)
    router.back()
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/settings'))
    await renderPage()
    router.back()
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/programmes/1'))
    await renderPage()

    expect(wrapper.get('.detail-cover').element).toBe(detail)
    expect(scroll().scrollTop).toBe(500)
  } finally {
    wrapper.unmount()
    coordinator.cancel()
    router.options.history.destroy()
    disposePinia(pinia)
  }
})
