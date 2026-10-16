import type { Programme, ProgrammeDate, ProgrammeContent } from '@shared/contracts/programmes'
import type { PlaybackRequest, PlaybackSession } from '@shared/contracts/media'
import type {
  DownloadRequest,
  DownloadStartResult,
  DownloadTask,
} from '@shared/contracts/downloads'
import type { Settings, SettingsSnapshot } from '@shared/contracts/settings'

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
  capabilities: { nativeDownloads: boolean; directorySelection: boolean }
  prepareExit?(prepare: () => Promise<boolean>): Promise<() => void>
  dispose(): Promise<void>
}
