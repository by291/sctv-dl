import type { DownloadTask } from '@shared/contracts/downloads'

import type { AppPlatform, NativeDownloadPort } from '@/shared/platform/ports'

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
    history: {
      list: async () => ({ entries: [], revision: 0, persisted: true, warning: null }),
      begin: async () => ({ id: crypto.randomUUID(), entry: null }),
      record: async () => ({ accepted: true, persisted: true }),
      end: async () => {},
      remove: async () => {},
      clear: async () => {},
      subscribe: async () => () => {},
      flush: async () => {},
      getWriteRevision: () => 0,
    },
    programmeCache: {
      read: async () => ({ epoch: 'fixture', snapshot: null, persisted: true, warning: null }),
      write: async (payload) => ({
        epoch: 'fixture',
        snapshot: {
          ...payload,
          version: 1,
          revision: crypto.randomUUID(),
          fetchedAt: new Date().toISOString(),
        },
        accepted: true,
        persisted: true,
        warning: null,
      }),
      readBrowseState: async () => ({
        epoch: 'fixture',
        value: null,
        persisted: true,
        warning: null,
      }),
      writeBrowseState: async () => ({ accepted: true, persisted: true }),
      clear: async () => ({ epoch: 'fixture-next' }),
      subscribeCleared: async () => () => {},
    },
    dispose: async () => {},
  }
}

export function createNativeDownloadFixture(): NativeDownloadPort {
  return {
    kind: 'native',
    start: async () => ({ kind: 'cancelled' }),
    snapshot: async () => ({ epoch: 'fixture', revision: 0, tasks: [] }),
    subscribeEvents: async () => () => {},
    act: async () => ({ kind: 'skipped', message: 'Task not found' }),
    openPlayback: async () => {
      throw new Error('No local playback fixture')
    },
    getDirectory: async () => null,
    chooseDirectory: async () => null,
  }
}

export function createDownloadTaskFixture(): DownloadTask {
  const content = { programmeId: '1', dateId: '2', contentId: '3' }

  return {
    id: 'job',
    attemptId: 'attempt-1',
    createdAt: '2026-10-17T00:00:00Z',
    content,
    metadata: {
      content,
      programmeName: 'News',
      broadcastDate: '2026-10-17',
      title: 'Episode',
      cover: null,
    },
    filename: 'news.mp4',
    quality: 'standard',
    state: 'running',
    receivedBytes: 1024,
    totalBytes: null,
    error: null,
    revision: 2,
    canResume: false,
    fileAvailable: false,
    hasPartial: true,
  }
}
