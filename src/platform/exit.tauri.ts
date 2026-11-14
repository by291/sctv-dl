import { Channel, invoke } from '@tauri-apps/api/core'

type ExitEvent = string | { cancelled: string }

// Register the native exit handshake and hold the edit freeze through its decision.
export async function prepareNativeExit(
  prepare: () => Promise<boolean>,
  setPreparing: (value: boolean) => void = () => {},
): Promise<() => void> {
  let active = true
  let preparingRequest: string | undefined

  async function acknowledge(requestId: string): Promise<void> {
    let saved = false
    try {
      saved = await prepare()
    } catch (cause) {
      console.error('Failed to save pending changes before exit', cause)
    }

    if (!active || preparingRequest !== requestId) {
      return
    }

    await invoke('complete_exit_preparation', { requestId, saved })
  }

  function releasePreparation(): void {
    if (preparingRequest) {
      preparingRequest = undefined
      setPreparing(false)
    }
  }

  const onEvent = new Channel<ExitEvent>()
  onEvent.onmessage = (event) => {
    if (!active) {
      return
    }

    if (typeof event !== 'string') {
      // A late cancellation must not unlock a newer exit attempt.
      if (event.cancelled === preparingRequest) {
        releasePreparation()
      }

      return
    }

    preparingRequest = event
    setPreparing(true)
    void acknowledge(event).catch((cause) => {
      if (active && preparingRequest === event) {
        console.error('Failed to acknowledge desktop exit preparation', cause)
      }
    })
  }

  const subscriptionId = await invoke<string>('subscribe_exit', { onEvent })

  return () => {
    if (!active) {
      return
    }

    active = false
    releasePreparation()
    // Local callbacks stop immediately; native teardown is best effort during process exit.
    void invoke('unsubscribe_exit', { subscriptionId }).catch(() => {})
  }
}
