// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from 'vitest'
import { prepareNativeExit } from '@/platform/exit.tauri'

type ExitEvent = string | { cancelled: string }

const bridge = vi.hoisted(() => ({
  invoke: vi.fn(),
  receive: undefined as undefined | { onmessage: (value: ExitEvent) => void },
}))
vi.mock('@tauri-apps/api/core', () => ({
  invoke: bridge.invoke,
  Channel: class {
    onmessage: (value: ExitEvent) => void = () => {}
    constructor() {
      bridge.receive = this
    }
  },
}))
beforeEach(() => bridge.invoke.mockReset().mockResolvedValue('subscription'))

it('acknowledges only after pending settings settle and reports failures', async () => {
  let finish!: (value: boolean) => void
  const stop = await prepareNativeExit(
    () =>
      new Promise((resolve) => {
        finish = resolve
      }),
  )
  bridge.receive!.onmessage('request')
  expect(bridge.invoke).not.toHaveBeenCalledWith('complete_exit_preparation', expect.anything())
  finish(true)
  await vi.waitFor(() =>
    expect(bridge.invoke).toHaveBeenCalledWith('complete_exit_preparation', {
      requestId: 'request',
      saved: true,
    }),
  )
  stop()
  const failed = await prepareNativeExit(async () => {
    throw new Error('write failed')
  })
  bridge.receive!.onmessage('failed')
  await vi.waitFor(() =>
    expect(bridge.invoke).toHaveBeenCalledWith('complete_exit_preparation', {
      requestId: 'failed',
      saved: false,
    }),
  )
  failed()
})

it('unsubscribes once and ignores events after disposal', async () => {
  const save = vi.fn(async () => true)
  const stop = await prepareNativeExit(save)
  stop()
  stop()
  bridge.receive!.onmessage('late')
  expect(save).not.toHaveBeenCalled()
  expect(
    bridge.invoke.mock.calls.filter(([command]) => command === 'unsubscribe_exit'),
  ).toHaveLength(1)
})

it('keeps edits frozen after acknowledging until the matching attempt is cancelled', async () => {
  const setPreparing = vi.fn()
  const prepare = vi.fn(async () => {
    expect(setPreparing).toHaveBeenLastCalledWith(true)

    return true
  })
  const stop = await prepareNativeExit(prepare, setPreparing)

  bridge.receive!.onmessage('current')
  await vi.waitFor(() =>
    expect(bridge.invoke).toHaveBeenCalledWith('complete_exit_preparation', {
      requestId: 'current',
      saved: true,
    }),
  )

  bridge.receive!.onmessage({ cancelled: 'old' })
  expect(setPreparing.mock.calls).toEqual([[true]])

  bridge.receive!.onmessage({ cancelled: 'current' })
  expect(setPreparing.mock.calls).toEqual([[true], [false]])
  stop()
})
