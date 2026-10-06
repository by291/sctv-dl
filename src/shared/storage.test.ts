// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { effectScope, nextTick } from 'vue'
import { z } from 'zod'
import { usePersistentState } from './storage'

afterEach(() => vi.restoreAllMocks())

describe('validated persistence', () => {
  it('uses pristine defaults if another tab sends damaged data after local edits', async () => {
    localStorage.removeItem('test:defaults')
    const scope = effectScope()
    const state = scope.run(() =>
      usePersistentState('test:defaults', { count: 0 }, z.object({ count: z.number() })),
    )!
    state.value.value.count = 4
    await nextTick()
    window.dispatchEvent(
      new StorageEvent('storage', {
        key: 'test:defaults',
        newValue: 'invalid',
        storageArea: localStorage,
      }),
    )
    await nextTick()
    expect(state.value.value).toEqual({ count: 0 })
    scope.stop()
  })

  it('recovers damaged JSON and persists later edits', async () => {
    localStorage.setItem('test:recovery', 'not json')
    const scope = effectScope()
    const state = scope.run(() =>
      usePersistentState('test:recovery', { count: 0 }, z.object({ count: z.number() })),
    )!
    expect(state.value.value).toEqual({ count: 0 })
    state.value.value.count = 2
    await nextTick()
    expect(JSON.parse(localStorage.getItem('test:recovery')!)).toEqual({ count: 2 })
    scope.stop()
  })

  it('reports denied writes while keeping in-memory state usable', async () => {
    const scope = effectScope()
    const state = scope.run(() =>
      usePersistentState('test:denied', { count: 0 }, z.object({ count: z.number() })),
    )!
    vi.spyOn(localStorage, 'setItem').mockImplementation(() => {
      throw new Error('quota')
    })
    state.value.value.count = 3
    await nextTick()
    expect(state.persisted.value).toBe(false)
    expect(state.value.value.count).toBe(3)
    scope.stop()
  })
})
