// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, disposePinia } from 'pinia'
import { createMemoryHistory, createRouter } from 'vue-router'
import { defineComponent, h } from 'vue'
import { NButton } from 'naive-ui'

import App from '@/App.vue'
import { platformKey } from '@/shared/platform/usePlatform'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'

import type { Component } from 'vue'
import type { VueWrapper } from '@vue/test-utils'

let wrapper: VueWrapper | undefined
let pinia: ReturnType<typeof createPinia>

afterEach(() => {
  wrapper?.unmount()
  disposePinia(pinia)
  document.body.removeAttribute('style')
  document.documentElement.removeAttribute('data-theme')
  document.head.querySelector('[cssr-id="n-global"]')?.remove()
  localStorage.clear()
})

describe('application startup typography', () => {
  it('styles navigation before the lazy page loads and keeps its typography unchanged', async () => {
    let resolvePage!: (page: Component) => void
    const page = new Promise<Component>((resolve) => {
      resolvePage = resolve
    })
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', name: 'library', component: () => page },
        { path: '/settings', component: { render: () => null } },
      ],
    })
    const navigation = router.push('/')
    pinia = createPinia()
    wrapper = mount(App, {
      attachTo: document.body,
      global: {
        plugins: [pinia, router],
        provide: { [platformKey as symbol]: createPlatformFixture() },
      },
    })
    await flushPromises()

    const link = wrapper.get('.nav-link').element
    const before = getComputedStyle(link)
    const initialTypography = { font: before.fontFamily, lineHeight: before.lineHeight }

    resolvePage(
      defineComponent({ render: () => h(NButton, null, { default: () => 'Loaded page' }) }),
    )
    await navigation
    await flushPromises()

    const after = getComputedStyle(link)
    expect(wrapper.get('button').text()).toBe('Loaded page')
    expect(initialTypography).toEqual({ font: after.fontFamily, lineHeight: after.lineHeight })
    expect(initialTypography.font).not.toBe('')
    expect(initialTypography.lineHeight).not.toBe('normal')
  })
})
