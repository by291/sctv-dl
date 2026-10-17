// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest'

import { createScrollRestoration } from '@/shared/navigation/scroll-restoration'
import { createAppRouter } from '@/router'

const restoration = createScrollRestoration()
const router = createAppRouter('web', restoration)

function location(path: string) {
  const route = router.resolve(path)

  return { ...route, name: route.name ?? undefined }
}

describe('route scroll restoration', () => {
  const scroll = router.options.scrollBehavior!

  it('leaves the current offset unchanged when clicking the already-active tab', async () => {
    const queue = vi.spyOn(restoration, 'scrollOnEnter')
    const current = location('/programmes/1')

    try {
      await scroll(current, current, null)
      expect(queue).not.toHaveBeenCalled()
    } finally {
      queue.mockRestore()
    }
  })

  it('lets the reactivated library restore its own scroll position', async () => {
    expect(await scroll(location('/'), location('/programmes/1'), null)).toBe(false)
    expect(await scroll(location('/'), location('/programmes/1'), { top: 600, left: 0 })).toBe(
      false,
    )
  })

  it('starts a newly opened programme at the top even when a previous visit has a saved offset', async () => {
    const workspace = document.createElement('div')
    workspace.id = 'workspace-scroll'
    document.body.append(workspace)
    const move = vi.spyOn(workspace, 'scrollTo').mockImplementation(() => {})
    const entry = restoration.begin('/programmes/1')

    try {
      expect(await scroll(location('/programmes/1'), location('/'), null)).toBe(false)
      expect(move).not.toHaveBeenCalled()
      restoration.pageEntered('/programmes/1')
      expect(move).toHaveBeenCalledWith({ left: 0, top: 0, behavior: 'instant' })

      // Content hydration must not replace this fresh entry with the persisted browse offset.
      Object.defineProperties(workspace, {
        scrollHeight: { value: 3000 },
        clientHeight: { value: 600 },
      })
      entry.restore(1800)
      expect(move).toHaveBeenLastCalledWith({ left: 0, top: 0, behavior: 'instant' })
    } finally {
      entry.cancel()
      restoration.cancel()
      workspace.remove()
    }
  })

  it('keeps persisted browse restoration available on an initial document load', async () => {
    await scroll(location('/programmes/1'), { ...location('/'), matched: [] }, null)

    expect(restoration.takeSavedPosition('/programmes/1')).toBeNull()
  })

  it('honours saved history positions on other routes', async () => {
    expect(
      await scroll(location('/programmes/1'), location('/settings'), {
        top: 240,
        left: 0,
      }),
    ).toBe(false)
    expect(restoration.takeSavedPosition('/programmes/1')).toEqual({ top: 240, left: 0 })
  })

  it('restores the workspace offset for a browser history entry instead of the window offset', async () => {
    const workspace = document.createElement('div')
    workspace.id = 'workspace-scroll'
    document.body.append(workspace)
    const coordinator = createScrollRestoration()
    const capture = vi.spyOn(coordinator, 'captureSavedPosition')
    const navigation = createAppRouter('web', coordinator)

    try {
      await navigation.push('/programmes/1')
      workspace.scrollTop = 420
      await navigation.push('/settings')
      capture.mockClear()

      navigation.back()

      await vi.waitFor(() => {
        expect(capture).toHaveBeenCalledWith('/programmes/1', { left: 0, top: 420 })
      })
      expect(window.scrollY).toBe(0)
    } finally {
      navigation.options.history.destroy()
      workspace.remove()
    }
  })
})

it('uses hash URLs for desktop routes so asset protocol reloads stay on the entry document', () => {
  const desktop = createAppRouter('tauri')
  expect(desktop.resolve('/programmes/12').href).toBe('#/programmes/12')
  expect(desktop.resolve('/settings').href).toBe('#/settings')
  expect(router.resolve('/settings').href).toBe('/settings')
})

it('registers the download task page only for desktop routing', () => {
  const desktop = createAppRouter('tauri')

  expect(desktop.resolve('/downloads').name).toBe('downloads')
  expect(desktop.resolve('/downloads').href).toBe('#/downloads')
  expect(router.resolve('/downloads').name).not.toBe('downloads')
})
