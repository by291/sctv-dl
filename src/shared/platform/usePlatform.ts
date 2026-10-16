import { inject } from 'vue'

import type { InjectionKey } from 'vue'
import type { AppPlatform } from '@/shared/platform/ports'

export const platformKey: InjectionKey<AppPlatform> = Symbol('application-platform')

export function usePlatform(): AppPlatform {
  const platform = inject(platformKey)
  if (!platform) {
    throw new Error('An application platform must be provided before mounting features.')
  }

  return platform
}
