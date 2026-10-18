// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { pageScrollPosition } from '@/shared/navigation/page-scroll'

afterEach(() => vi.restoreAllMocks())

it('captures a top-edge bounce as zero without changing the live scroll position', () => {
  const element = document.createElement('div')
  element.scrollTop = -42.5
  element.scrollLeft = -8

  expect(pageScrollPosition(element)).toEqual({ left: 0, top: 0 })
  expect(element.scrollTop).toBe(-42.5)
})

it('preserves positive fractional scroll positions', () => {
  const element = document.createElement('div')
  element.scrollTop = 320.75
  element.scrollLeft = 12.5

  expect(pageScrollPosition(element)).toEqual({ left: 12.5, top: 320.75 })
})

it('normalizes bounce offsets from the window fallback too', () => {
  vi.spyOn(window, 'scrollY', 'get').mockReturnValue(-28)
  vi.spyOn(window, 'scrollX', 'get').mockReturnValue(-4)

  expect(pageScrollPosition(window)).toEqual({ left: 0, top: 0 })
})
