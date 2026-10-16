// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest'

import { createAppRouter } from '@/router'

const router = createAppRouter('web')

function location(path: string) {
  const route = router.resolve(path)

  return { ...route, name: route.name ?? undefined }
}

describe('route scroll restoration', () => {
  const scroll = router.options.scrollBehavior!

  it('lets the reactivated library restore its own scroll position', async () => {
    expect(await scroll(location('/'), location('/programmes/1'), null)).toBe(false)
    expect(await scroll(location('/'), location('/programmes/1'), { top: 600, left: 0 })).toBe(
      false,
    )
  })

  it('opens programme details at the top during ordinary navigation', async () => {
    expect(await scroll(location('/programmes/1'), location('/'), null)).toEqual({
      top: 0,
    })
  })

  it('honours saved history positions on other routes', async () => {
    expect(
      await scroll(location('/programmes/1'), location('/settings'), {
        top: 240,
        left: 0,
      }),
    ).toEqual({ top: 240, left: 0 })
  })
})

it('uses hash URLs for desktop routes so asset protocol reloads stay on the entry document', () => {
  const desktop = createAppRouter('tauri')
  expect(desktop.resolve('/programmes/12').href).toBe('#/programmes/12')
  expect(desktop.resolve('/settings').href).toBe('#/settings')
  expect(router.resolve('/settings').href).toBe('/settings')
})
