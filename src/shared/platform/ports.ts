import type { Programme, ProgrammeDate, ProgrammeContent } from '@shared/contracts/programmes'
import type { PlaybackRequest, PlaybackSession } from '@shared/contracts/media'
import type {
  DownloadRequest,
  DownloadStartResult,
  DownloadTask,
  DownloadSnapshot,
  DownloadEvent,
  DownloadActionRequest,
  DownloadActionResult,
} from '@shared/contracts/downloads'
import type { Settings, SettingsSnapshot } from '@shared/contracts/settings'
import type {
  ProgrammeCacheKey,
  ProgrammeCachePayload,
  ArchiveBrowseState,
  CacheRead,
  CacheWriteResult,
  BrowseStateRead,
} from '@shared/contracts/programme-cache'
import type { ContentRef } from '@shared/contracts/programmes'
import type {
  HistoryMetadata,
  HistorySample,
  HistorySession,
  HistorySnapshot,
} from '@shared/contracts/history'

export interface HistoryPort {
  list(): Promise<HistorySnapshot>
  begin(metadata: HistoryMetadata): Promise<HistorySession>
  record(
    sessionId: string,
    sample: HistorySample,
  ): Promise<{ accepted: boolean; persisted: boolean }>
  end(sessionId: string): Promise<void>
  remove(content: ContentRef): Promise<void>
  clear(): Promise<void>
  subscribe(listener: (snapshot: HistorySnapshot) => void): Promise<() => void>
  flush(): Promise<void>
  getWriteRevision(): number
}

export interface ProgrammeCachePort {
  read(key: ProgrammeCacheKey): Promise<CacheRead>
  write(payload: ProgrammeCachePayload, expectedEpoch: string): Promise<CacheWriteResult>
  readBrowseState(programmeId: string): Promise<BrowseStateRead>
  writeBrowseState(
    value: ArchiveBrowseState,
    expectedEpoch: string,
  ): Promise<{ accepted: boolean; persisted: boolean }>
  clear(): Promise<{ epoch: string }>
  subscribeCleared(listener: (epoch: string) => void): Promise<() => void>
}

export interface ProgrammeApi {
  programmes(signal?: AbortSignal): Promise<Programme[]>
  dates(programmeId: string, signal?: AbortSignal): Promise<ProgrammeDate[]>
  contents(programmeId: string, dateId: string, signal?: AbortSignal): Promise<ProgrammeContent[]>
}

export interface PlaybackPort {
  open(request: PlaybackRequest, signal?: AbortSignal): Promise<PlaybackSession>
  close(id: string): Promise<void>
}

export interface BrowserDownloadPort {
  kind: 'browser'
  start(request: DownloadRequest): Promise<DownloadStartResult>
}

export interface NativeDownloadPort {
  kind: 'native'
  start(request: DownloadRequest): Promise<DownloadStartResult>
  list(): Promise<DownloadTask[]>
  subscribe(listener: (task: DownloadTask) => void): Promise<() => void>
  cancel(id: string): Promise<void>
  snapshot(): Promise<DownloadSnapshot>
  subscribeEvents(listener: (event: DownloadEvent) => void): Promise<() => void>
  act(request: DownloadActionRequest): Promise<DownloadActionResult>
  openPlayback(taskId: string, signal?: AbortSignal): Promise<PlaybackSession>
  getDirectory(): Promise<string | null>
  chooseDirectory(): Promise<string | null>
}

export interface SettingsPort {
  load(): Promise<SettingsSnapshot>
  save(value: Settings): Promise<void>
  subscribe(listener: (value: Settings) => void): Promise<() => void>
}

export interface AppPlatform {
  kind: 'web' | 'tauri'
  programmes: ProgrammeApi
  playback: PlaybackPort
  downloads: BrowserDownloadPort | NativeDownloadPort
  settings: SettingsPort
  history: HistoryPort
  programmeCache: ProgrammeCachePort
  capabilities: { nativeDownloads: boolean; directorySelection: boolean }
  prepareExit?(prepare: () => Promise<boolean>): Promise<() => void>
  dispose(): Promise<void>
}
