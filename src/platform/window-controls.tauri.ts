import { getCurrentWindow } from '@tauri-apps/api/window'

import type { WindowControlsPort } from '@/shared/platform/ports'

export function createTauriWindowControls(): WindowControlsPort {
  // Resolve the window lazily so composing the platform never requires a live webview.
  const current = () => getCurrentWindow()

  return {
    minimize: () => current().minimize(),
    toggleMaximize: () => current().toggleMaximize(),
    close: () => current().close(),
    isMaximized: () => current().isMaximized(),
    onResized: (listener) => current().onResized(() => listener()),
  }
}
