import { Channel, invoke } from '@tauri-apps/api/core'

export async function prepareNativeExit(prepare: () => Promise<boolean>): Promise<() => void> {
  let active = true
  const onEvent = new Channel<string>()
  onEvent.onmessage = (requestId) => {
    if (!active) {
      return
    }

    void (async () => {
      let saved = false
      try {
        saved = await prepare()
      } finally {
        await invoke('complete_exit_preparation', { requestId, saved })
      }
    })().catch(() => {
      // A failed save still sends saved=false; acknowledgement can fail during native exit.
    })
  }

  const subscriptionId = await invoke<string>('subscribe_exit', { onEvent })

  return () => {
    if (!active) {
      return
    }

    active = false
    // Local callbacks stop immediately; native teardown is best effort during process exit.
    void invoke('unsubscribe_exit', { subscriptionId }).catch(() => {})
  }
}
