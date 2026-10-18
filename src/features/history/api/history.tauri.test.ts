// @vitest-environment happy-dom
import { afterEach, expect, it } from 'vitest'
import { mockIPC, clearMocks } from '@tauri-apps/api/mocks'

import { createTauriHistory } from '@/features/history/api/history.tauri'

const metadata = {
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  programmeName: 'News',
  broadcastDate: '2026-10-17',
  title: 'Episode',
  cover: null,
}
afterEach(clearMocks)

it('validates native history and sends stable session IDs and sample sequences', async () => {
  const calls: unknown[] = []
  mockIPC((command, args) => {
    calls.push([command, args])
    if (command === 'begin_history') {
      return { id: 'session', entry: null }
    }

    if (command === 'record_history') {
      return { accepted: true, persisted: true }
    }

    if (command === 'list_history') {
      return { entries: [], revision: 1, persisted: true, warning: null }
    }

    return null
  })
  const adapter = createTauriHistory()
  const session = await adapter.port.begin(metadata)
  const sample = { positionMs: 300000, durationMs: 600000, sequence: 1, ended: false }
  await adapter.port.record(session.id, sample)
  expect(calls[1]).toEqual(['record_history', { sessionId: 'session', sample }])
  expect(adapter.port.getWriteRevision()).toBe(2)
  await adapter.port.flush()
  await adapter.dispose()
  mockIPC(() => ({ entries: 'invalid' }))
  await expect(createTauriHistory().port.list()).rejects.toThrow()
})

it('reports failure to flush when native persistence is unavailable', async () => {
  mockIPC(() => ({ entries: [], revision: 0, persisted: false, warning: 'Disk unavailable' }))
  const adapter = createTauriHistory()
  await expect(adapter.port.flush()).rejects.toThrow('Disk unavailable')
  await adapter.dispose()
})

it('retains failed queued writes until their explicit retry succeeds', async () => {
  let fail = true
  mockIPC((command) => {
    if (command === 'record_history') {
      if (fail) {
        throw { code: 'storage', message: 'Disk unavailable' }
      }

      return { accepted: true, persisted: true }
    }

    return { entries: [], revision: 1, persisted: true, warning: null }
  })
  const adapter = createTauriHistory()
  const sample = { positionMs: 300000, durationMs: 600000, sequence: 1, ended: false }
  await expect(adapter.port.record('session', sample)).rejects.toThrow('Disk unavailable')
  await expect(adapter.port.flush()).rejects.toThrow('观看历史有未保存的更改')

  fail = false
  await adapter.port.record('session', sample)
  await expect(adapter.port.flush()).resolves.toBeUndefined()
  await adapter.dispose()
})
