// @vitest-environment happy-dom
import { flushPromises, mount } from '@vue/test-utils'
import { expect, it, vi } from 'vitest'

import WindowTitleBar from '@/layouts/WindowTitleBar.vue'

import type { WindowControlsPort } from '@/shared/platform/ports'

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((finish) => {
    resolve = finish
  })

  return { promise, resolve }
}

function windowControls(overrides: Partial<WindowControlsPort>): WindowControlsPort {
  return {
    minimize: async () => {},
    toggleMaximize: async () => {},
    close: async () => {},
    isMaximized: async () => false,
    onResized: async () => () => {},
    ...overrides,
  }
}

it('keeps the latest native window state when resize results arrive out of order', async () => {
  const oldReading = deferred<boolean>()
  let resize: (() => void) | undefined
  const controls = windowControls({
    isMaximized: vi.fn().mockReturnValueOnce(oldReading.promise).mockResolvedValue(true),
    onResized: async (listener) => {
      resize = listener

      return () => {}
    },
  })
  const wrapper = mount(WindowTitleBar, { props: { controls } })
  await flushPromises()

  resize?.()
  await flushPromises()
  oldReading.resolve(false)
  await flushPromises()

  expect(wrapper.find('button[aria-label="还原"]').exists()).toBe(true)
  wrapper.unmount()
})

it('observes the current maximized state after asynchronous listener registration', async () => {
  const registration = deferred<() => void>()
  let isMaximized = false
  const controls = windowControls({
    isMaximized: async () => isMaximized,
    onResized: () => registration.promise,
  })
  const wrapper = mount(WindowTitleBar, { props: { controls } })

  isMaximized = true
  registration.resolve(() => {})
  await flushPromises()

  expect(wrapper.find('button[aria-label="还原"]').exists()).toBe(true)
  wrapper.unmount()
})
