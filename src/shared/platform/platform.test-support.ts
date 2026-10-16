import type { AppPlatform } from '@/shared/platform/ports'

export function createPlatformFixture(): AppPlatform {
  return {
    kind: 'web',
    programmes: { programmes: async () => [], dates: async () => [], contents: async () => [] },
    playback: {
      open: async () => {
        throw new Error('No fixture playback source')
      },
      close: async () => {},
    },
    downloads: { kind: 'browser', start: async () => ({ kind: 'cancelled' }) },
    settings: {
      load: async () => ({
        value: { quality: 'standard', theme: 'system', favourites: [] },
        persisted: true,
      }),
      save: async () => {},
      subscribe: async () => () => {},
    },
    capabilities: { nativeDownloads: false, directorySelection: false },
    dispose: async () => {},
  }
}
