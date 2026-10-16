import { isTauri } from '@tauri-apps/api/core'

import type { AppPlatform } from '@/shared/platform/ports'

export async function createPlatform(): Promise<AppPlatform> {
  if (isTauri()) {
    const { createTauriPlatform } = await import('@/platform/tauri-platform')

    return createTauriPlatform()
  }

  const { createWebPlatform } = await import('@/platform/web-platform')

  return createWebPlatform()
}
