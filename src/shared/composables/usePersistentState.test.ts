// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { effectScope, nextTick } from 'vue'
import { z } from 'zod'
import { usePersistentState } from '@/shared/composables/usePersistentState'

const originalSetItem = localStorage.setItem
const scopes: ReturnType<typeof effectScope>[] = []

beforeEach(() => {
  localStorage.clear()
})

afterEach(() => {
  for (const scope of scopes.splice(0)) {
    scope.stop()
  }

  // happy-dom's Storage proxy hides method descriptors from Vitest's spy restoration.
  Object.defineProperty(localStorage, 'setItem', {
    configurable: true,
    writable: true,
    value: originalSetItem,
  })
  vi.restoreAllMocks()
})

function createScope() {
  const scope = effectScope()
  scopes.push(scope)

  return scope
}

describe('validated persistence', () => {
  it('uses pristine defaults if another tab sends damaged data after local edits', async () => {
    localStorage.removeItem('test:defaults')
    const scope = createScope()
    const state = scope.run(() =>
      usePersistentState({
        key: 'test:defaults',
        defaults: { count: 0 },
        schema: z.object({ count: z.number() }),
      }),
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
  })

  it('recovers damaged JSON and persists later edits', async () => {
    localStorage.setItem('test:recovery', 'not json')
    const scope = createScope()
    const state = scope.run(() =>
      usePersistentState({
        key: 'test:recovery',
        defaults: { count: 0 },
        schema: z.object({ count: z.number() }),
      }),
    )!
    expect(state.value.value).toEqual({ count: 0 })
    state.value.value.count = 2
    await nextTick()
    expect(JSON.parse(localStorage.getItem('test:recovery')!)).toEqual({ count: 2 })
  })

  it('reports denied writes while keeping in-memory state usable', async () => {
    const scope = createScope()
    const state = scope.run(() =>
      usePersistentState({
        key: 'test:denied',
        defaults: { count: 0 },
        schema: z.object({ count: z.number() }),
      }),
    )!
    vi.spyOn(localStorage, 'setItem').mockImplementation(() => {
      throw new Error('quota')
    })
    state.value.value.count = 3
    await nextTick()
    expect(state.persisted.value).toBe(false)
    expect(state.value.value.count).toBe(3)
  })
})
