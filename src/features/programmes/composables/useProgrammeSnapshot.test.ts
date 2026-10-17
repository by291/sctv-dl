import { afterEach, describe, expect, it, vi } from 'vitest'
import { effectScope } from 'vue'
import { useProgrammeSnapshot } from '@/features/programmes/composables/useProgrammeSnapshot'
import type { ProgrammeCachePort } from '@/shared/platform/ports'
import type { CacheRead, ProgrammeSnapshot } from '@shared/contracts/programme-cache'

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (cause: unknown) => void
  const promise = new Promise<T>((yes, no) => {
    resolve = yes
    reject = no
  })

  return { promise, resolve, reject }
}

const snapshot: Extract<ProgrammeSnapshot, { kind: 'catalogue' }> = {
  kind: 'catalogue',
  version: 1,
  revision: 'old',
  fetchedAt: '2026-10-17T00:00:00Z',
  items: [{ id: '1', name: 'Old', cover: null }],
}
const fresh: typeof snapshot.items = [{ id: '2', name: 'Fresh', cover: null }]
const scopes: ReturnType<typeof effectScope>[] = []
afterEach(() => {
  scopes.splice(0).forEach((scope) => scope.stop())
})

function fixture(cached: ProgrammeSnapshot | null = snapshot) {
  let cleared: (epoch: string) => void = () => {}

  const cache: ProgrammeCachePort = {
    read: vi
      .fn()
      .mockResolvedValue({ epoch: 'epoch', snapshot: cached, persisted: true, warning: null }),
    write: vi.fn(async (payload) => ({
      epoch: 'epoch',
      snapshot: {
        ...payload,
        version: 1 as const,
        revision: 'new',
        fetchedAt: new Date().toISOString(),
      },
      persisted: true,
      warning: null,
      accepted: true,
    })),
    readBrowseState: vi.fn(),
    writeBrowseState: vi.fn(),
    clear: vi.fn(),
    subscribeCleared: vi.fn(async (listener) => {
      cleared = listener

      return vi.fn()
    }),
  }
  const scope = effectScope()
  scopes.push(scope)
  const owner = scope.run(() => useProgrammeSnapshot('catalogue', cache))!

  return { owner, cache, scope, clear: () => cleared('new-epoch') }
}

async function settle() {
  for (let i = 0; i < 12; i++) {
    await Promise.resolve()
  }
}

describe('programme snapshot refresh ownership', () => {
  it('renders warm cache before the network and holds meaningful changes for acceptance', async () => {
    const { owner } = fixture()
    const live = deferred<typeof fresh>()
    const loading = owner.load({ kind: 'catalogue' }, () => live.promise)
    await settle()
    expect(owner.accepted.value?.items).toEqual(snapshot.items)
    expect(owner.loading.value).toBe(false)
    expect(owner.cached.value).toBe(true)
    live.resolve(fresh)
    await loading
    expect(owner.accepted.value?.items).toEqual(snapshot.items)
    expect(owner.pendingUpdate.value).toBe(true)
    owner.acceptUpdate(true)
    expect(owner.accepted.value?.items).toEqual(snapshot.items)
    owner.acceptUpdate(false)
    expect(owner.accepted.value?.items).toEqual(fresh)
  })
  it('keeps valid empty cache visible after a network failure', async () => {
    const { owner } = fixture({ ...snapshot, items: [] })
    await owner.load({ kind: 'catalogue' }, async () => {
      throw new Error('Offline')
    })
    expect(owner.accepted.value?.items).toEqual([])
    expect(owner.error.value).toBe('')
    expect(owner.refreshError.value).toContain('Offline')
  })
  it('does not roll back a fast network result when the old cache read arrives later', async () => {
    const { owner, cache } = fixture()
    const cached = deferred<CacheRead>()
    vi.mocked(cache.read).mockReturnValue(cached.promise)
    const loading = owner.load({ kind: 'catalogue' }, async () => fresh)
    await settle()
    expect(owner.accepted.value?.items).toEqual(fresh)
    cached.resolve({ epoch: 'epoch', snapshot, persisted: true, warning: null })
    await loading
    expect(owner.accepted.value?.items).toEqual(fresh)
    expect(owner.pendingUpdate.value).toBe(false)
  })
  it('cancels pre-clear work, preserves visible data, and never refetches automatically', async () => {
    const { owner, cache, clear } = fixture()
    const live = deferred<typeof fresh>()
    const fetcher = vi.fn(() => live.promise)
    const loading = owner.load({ kind: 'catalogue' }, fetcher)
    await settle()
    clear()
    live.resolve(fresh)
    await loading
    expect(owner.accepted.value?.items).toEqual(snapshot.items)
    expect(owner.cached.value).toBe(false)
    expect(owner.pendingUpdate.value).toBe(false)
    expect(cache.write).not.toHaveBeenCalled()
    expect(fetcher).toHaveBeenCalledOnce()
  })
  it('rejects stale results from superseded refreshes and disposed owners', async () => {
    const { owner, cache, scope } = fixture(null)
    const old = deferred<typeof fresh>()
    const first = owner.load({ kind: 'catalogue' }, () => old.promise)
    await owner.load({ kind: 'catalogue' }, async () => fresh)
    old.resolve(snapshot.items)
    await first
    expect(owner.accepted.value?.items).toEqual(fresh)
    expect(cache.write).toHaveBeenCalledOnce()
    const last = deferred<typeof fresh>()
    const loading = owner.load({ kind: 'catalogue' }, () => last.promise)
    scope.stop()
    last.resolve([])
    await loading
    expect(owner.accepted.value?.items).toEqual(fresh)
  })
})

it('establishes invalidation observation before admitting a live refresh', async () => {
  const ready = deferred<() => void>()
  const { cache, scope } = fixture(null)
  scope.stop()
  vi.mocked(cache.subscribeCleared).mockReturnValue(ready.promise)
  const ownerScope = effectScope()
  scopes.push(ownerScope)
  const owner = ownerScope.run(() => useProgrammeSnapshot('catalogue', cache))!
  const fetcher = vi.fn(async () => fresh)
  const loading = owner.load({ kind: 'catalogue' }, fetcher)
  await settle()
  expect(fetcher).not.toHaveBeenCalled()
  ready.resolve(() => {})
  await loading
  expect(fetcher).toHaveBeenCalledOnce()
})
