// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { createScrollRestoration } from '@/shared/navigation/scroll-restoration'

afterEach(() => vi.restoreAllMocks())

function viewport(height = 1600) {
  Object.defineProperty(document.documentElement, 'scrollHeight', {
    configurable: true,
    value: height,
  })
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: 600 })

  return vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
}

it('restores persisted offsets and gives explicit browser back positions precedence', () => {
  const scroll = viewport()
  const owner = createScrollRestoration()
  const first = owner.begin('/programmes/1')
  owner.captureSavedPosition('/programmes/1', { left: 0, top: 240 })
  expect(first.restore(800)).toBe(true)
  expect(scroll).toHaveBeenLastCalledWith({ left: 0, top: 240, behavior: 'instant' })
  const second = owner.begin('/programmes/1')
  second.restore(700)
  expect(scroll).toHaveBeenLastCalledWith({ left: 0, top: 700, behavior: 'instant' })
})
it('clamps short lists and ignores ordinary programmatic scroll events', () => {
  const scroll = viewport(900)
  const owner = createScrollRestoration()
  const entry = owner.begin('/programmes/1')
  window.dispatchEvent(new Event('scroll'))
  entry.restore(900)
  expect(scroll).toHaveBeenCalledWith({ left: 0, top: 300, behavior: 'instant' })
})
it.each(['wheel', 'touchstart', 'keydown'])(
  'abandons delayed restoration on %s user intent',
  (event) => {
    const scroll = viewport()
    const entry = createScrollRestoration().begin('/programmes/1')
    window.dispatchEvent(
      event === 'keydown' ? new KeyboardEvent(event, { key: 'PageDown' }) : new Event(event),
    )
    expect(entry.restore(700)).toBe(false)
    expect(scroll).not.toHaveBeenCalled()
  },
)
it('prevents an earlier route entry from restoring after navigation', () => {
  const scroll = viewport()
  const owner = createScrollRestoration()
  const old = owner.begin('/programmes/1')
  owner.cancel()
  const current = owner.begin('/programmes/2')
  expect(old.restore(800)).toBe(false)
  expect(current.restore(100)).toBe(true)
  expect(scroll).toHaveBeenCalledTimes(1)
})

it('restores and clamps inside the workspace without moving the document', () => {
  const windowScroll = viewport()
  const workspace = document.createElement('div')
  workspace.id = 'workspace-scroll'
  Object.defineProperties(workspace, {
    scrollHeight: { value: 1500 },
    clientHeight: { value: 600 },
  })
  const scroll = vi.spyOn(workspace, 'scrollTo').mockImplementation(() => {})
  document.body.append(workspace)

  try {
    const entry = createScrollRestoration().begin('/programmes/1')
    entry.restore(1200)

    expect(scroll).toHaveBeenCalledWith({ left: 0, top: 900, behavior: 'instant' })
    expect(windowScroll).not.toHaveBeenCalled()
  } finally {
    workspace.remove()
  }
})

it('waits for the destination to enter before resetting the shared page position', () => {
  const scroll = viewport()
  const owner = createScrollRestoration()
  owner.scrollOnEnter('/settings', { left: 0, top: 0 })
  expect(scroll).not.toHaveBeenCalled()

  owner.pageEntered('/settings')
  expect(scroll).toHaveBeenCalledWith({ left: 0, top: 0, behavior: 'instant' })
})

it('keeps a retained tab position instead of applying the fresh-route reset', () => {
  const scroll = viewport()
  const owner = createScrollRestoration()
  owner.pageEntered('/history', { left: 0, top: 640 })
  owner.scrollOnEnter('/history', { left: 0, top: 0 })

  expect(scroll).toHaveBeenCalledWith({ left: 0, top: 640, behavior: 'instant' })
})

it('discards pending scroll when a newer navigation supersedes the transition', () => {
  const scroll = viewport()
  const owner = createScrollRestoration()
  owner.scrollOnEnter('/settings', { left: 0, top: 400 })
  owner.cancel()
  owner.pageEntered('/settings')

  expect(scroll).not.toHaveBeenCalled()
})

it('honours an older browser history offset instead of the retained tab offset', () => {
  const scroll = viewport()
  const owner = createScrollRestoration()
  owner.pageEntered('/programmes/1', { left: 0, top: 900 })
  owner.scrollOnEnter('/programmes/1', { left: 0, top: 500 }, 'history')

  expect(scroll).toHaveBeenCalledWith({ left: 0, top: 500, behavior: 'instant' })
})
