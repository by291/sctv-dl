// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { defineComponent } from 'vue'

import { useDownloadDirectory } from '@/features/settings/composables/useDownloadDirectory'

import type { VueWrapper } from '@vue/test-utils'
import type { BrowserDownloadPort, NativeDownloadPort } from '@/shared/platform/ports'

let wrapper: VueWrapper | undefined

afterEach(() => {
  wrapper?.unmount()
  wrapper = undefined
})

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (cause: Error) => void
  const promise = new Promise<T>((done, fail) => {
    resolve = done
    reject = fail
  })

  return { promise, resolve, reject }
}

function nativeDownloads(overrides: Partial<NativeDownloadPort> = {}): NativeDownloadPort {
  return {
    kind: 'native',
    getDirectory: async () => '/initial',
    chooseDirectory: async () => '/selected',
    start: async () => ({ kind: 'cancelled' }),
    list: async () => [],
    subscribe: async () => () => {},
    cancel: async () => {},
    ...overrides,
  }
}

function mountDirectory(downloads: BrowserDownloadPort | NativeDownloadPort) {
  let directory!: ReturnType<typeof useDownloadDirectory>
  wrapper = mount(
    defineComponent({
      setup() {
        directory = useDownloadDirectory(downloads)

        return () => null
      },
    }),
  )

  return directory
}

describe('download directory workflow', () => {
  it('leaves directory selection unavailable for browser downloads', async () => {
    const directory = mountDirectory({
      kind: 'browser',
      start: async () => ({ kind: 'cancelled' }),
    })
    await directory.chooseDirectory()

    expect(directory.canChooseDirectory).toBe(false)
    expect(directory.directory.value).toBeNull()
    expect(directory.error.value).toBe('')
    expect(directory.busy.value).toBe(false)
  })

  it.each(['success', 'failure'])(
    'ignores stale initial directory %s after a newer selection',
    async (outcome) => {
      const initial = deferred<string | null>()
      const directory = mountDirectory(nativeDownloads({ getDirectory: () => initial.promise }))
      await directory.chooseDirectory()

      if (outcome === 'success') {
        initial.resolve('/obsolete')
      } else {
        initial.reject(new Error('Obsolete directory error'))
      }

      await flushPromises()
      expect(directory.directory.value).toBe('/selected')
      expect(directory.error.value).toBe('')
    },
  )

  it('reloads the saved directory when the user dismisses the picker', async () => {
    let saved = '/initial'
    const directory = mountDirectory(
      nativeDownloads({
        getDirectory: async () => saved,
        chooseDirectory: async () => null,
      }),
    )
    await flushPromises()
    saved = '/changed-elsewhere'
    await directory.chooseDirectory()

    expect(directory.directory.value).toBe('/changed-elsewhere')
    expect(directory.error.value).toBe('')
    expect(directory.busy.value).toBe(false)
  })

  it('retains a recoverable error after cancellation and clears it after a successful selection', async () => {
    let selected: string | null = null
    const directory = mountDirectory(
      nativeDownloads({
        getDirectory: async () => {
          throw new Error('Directory unavailable')
        },
        chooseDirectory: async () => selected,
      }),
    )
    await flushPromises()
    await directory.chooseDirectory()
    expect(directory.error.value).toBe('Directory unavailable')
    expect(directory.busy.value).toBe(false)

    selected = '/recovered'
    await directory.chooseDirectory()
    expect(directory.directory.value).toBe('/recovered')
    expect(directory.error.value).toBe('')
  })

  it('prevents duplicate pickers and permits a retry after a failed selection', async () => {
    const selection = deferred<string | null>()
    const choose = vi.fn().mockReturnValueOnce(selection.promise).mockResolvedValue('/recovered')
    const directory = mountDirectory(nativeDownloads({ chooseDirectory: choose }))
    await flushPromises()
    const choosing = directory.chooseDirectory()
    await directory.chooseDirectory()
    expect(choose).toHaveBeenCalledOnce()
    expect(directory.busy.value).toBe(true)

    selection.reject(new Error('Picker failed'))
    await choosing
    expect(directory.error.value).toBe('Picker failed')
    expect(directory.busy.value).toBe(false)

    await directory.chooseDirectory()
    expect(directory.directory.value).toBe('/recovered')
    expect(directory.error.value).toBe('')
  })

  it.each([
    { action: 'load', outcome: 'success' },
    { action: 'load', outcome: 'failure' },
    { action: 'choose', outcome: 'success' },
    { action: 'choose', outcome: 'failure' },
  ])('ignores a late $action $outcome after disposal', async ({ action, outcome }) => {
    const pending = deferred<string | null>()
    const directory = mountDirectory(
      nativeDownloads({
        getDirectory: action === 'load' ? () => pending.promise : async () => '/initial',
        chooseDirectory: () => pending.promise,
      }),
    )
    await flushPromises()
    const before = directory.directory.value
    const choosing = action === 'choose' ? directory.chooseDirectory() : undefined
    wrapper!.unmount()
    wrapper = undefined

    if (outcome === 'success') {
      pending.resolve('/late')
    } else {
      pending.reject(new Error('Late directory error'))
    }

    await choosing
    await flushPromises()
    expect(directory.directory.value).toBe(before)
    expect(directory.error.value).toBe('')
  })
})
