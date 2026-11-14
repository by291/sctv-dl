import type { Programme, ProgrammeDate, ProgrammeContent } from '@shared/contracts/programmes'
import type { PlaybackRequest, PlaybackSession } from '@shared/contracts/media'
import type {
  DownloadRequest,
  DownloadStartResult,
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
  // Read recent history and report whether it was recovered from durable storage.
  list(): Promise<HistorySnapshot>
  // Acquire playback ownership and return the last saved entry for this content.
  begin(metadata: HistoryMetadata): Promise<HistorySession>
  // Save a newer sample only while its history session owns the content.
  record(
    sessionId: string,
    sample: HistorySample,
  ): Promise<{ accepted: boolean; persisted: boolean }>
  // Release the session after the caller has drained its progress writes.
  end(sessionId: string): Promise<void>
  // Remove an entry and invalidate any session that could recreate it.
  remove(content: ContentRef): Promise<void>
  // Clear all entries and invalidate their sessions.
  clear(): Promise<void>
  // Observe revisioned snapshots until the returned handle is called.
  subscribe(listener: (snapshot: HistorySnapshot) => void): Promise<() => void>
  // Wait for queued history writes and surface unresolved persistence failures.
  flush(): Promise<void>
  // Report how much write work has been issued so exit can detect new work.
  getWriteRevision(): number
}

export interface ProgrammeCachePort {
  // Read one metadata snapshot and the epoch that owns it.
  read(key: ProgrammeCacheKey): Promise<CacheRead>
  // Save a metadata snapshot only if its owner still holds the current epoch.
  write(payload: ProgrammeCachePayload, expectedEpoch: string): Promise<CacheWriteResult>
  // Restore a programme's last date, sort, and workspace position.
  readBrowseState(programmeId: string): Promise<BrowseStateRead>
  // Save browse state only while the caller owns the current epoch.
  writeBrowseState(
    value: ArchiveBrowseState,
    expectedEpoch: string,
  ): Promise<{ accepted: boolean; persisted: boolean }>
  // Invalidate old writers by advancing the epoch before deleting obsolete data.
  clear(): Promise<{ epoch: string }>
  // Observe cache invalidation before starting reads or network requests.
  subscribeCleared(listener: (epoch: string) => void): Promise<() => void>
}

export interface ProgrammeApi {
  // Read the normalized programme catalogue.
  programmes(signal?: AbortSignal): Promise<Programme[]>
  // Read the broadcast dates for a programme.
  dates(programmeId: string, signal?: AbortSignal): Promise<ProgrammeDate[]>
  // Read the clips for a specific broadcast ID.
  contents(programmeId: string, dateId: string, signal?: AbortSignal): Promise<ProgrammeContent[]>
}

export interface PlaybackPort {
  // Prepare playable sources and return the session that owns them.
  open(request: PlaybackRequest, signal?: AbortSignal): Promise<PlaybackSession>
  // Release resources held by the playback session.
  close(id: string): Promise<void>
}

export interface BrowserDownloadPort {
  kind: 'browser'

  // Hand off validated attachments to the browser.
  start(request: DownloadRequest): Promise<DownloadStartResult>
}

export interface NativeDownloadPort {
  kind: 'native'

  // Queue transfers in the native download service.
  start(request: DownloadRequest): Promise<DownloadStartResult>
  // Read the current native task list and its process revision.
  snapshot(): Promise<DownloadSnapshot>
  // Observe revisioned task changes until unsubscribed.
  subscribeEvents(listener: (event: DownloadEvent) => void): Promise<() => void>
  // Apply an action to the identified task attempt.
  act(request: DownloadActionRequest): Promise<DownloadActionResult>
  // Open a completed local file under a playback session.
  openPlayback(taskId: string, signal?: AbortSignal): Promise<PlaybackSession>
  // Read the currently configured native download directory.
  getDirectory(): Promise<string | null>
  // Open the native directory picker and return its selection.
  chooseDirectory(): Promise<string | null>
}

export interface SettingsPort {
  // Read the effective preferences and their persistence status.
  load(): Promise<SettingsSnapshot>
  // Persist a complete validated preferences snapshot.
  save(value: Settings): Promise<void>
  // Observe settings changes until unsubscribed.
  subscribe(listener: (value: Settings) => void): Promise<() => void>
}

// Native window chrome is owned by the shell; the web build omits this port.
export interface WindowControlsPort {
  // Minimize the app window.
  minimize(): Promise<void>
  // Toggle between normal and maximized window geometry.
  toggleMaximize(): Promise<void>
  // Request that the app window close.
  close(): Promise<void>
  // Read current native window geometry for the title bar.
  isMaximized(): Promise<boolean>
  // Observe window geometry changes until unsubscribed.
  onResized(listener: () => void): Promise<() => void>
}

export interface AppPlatform {
  kind: 'web' | 'tauri'
  programmes: ProgrammeApi
  playback: PlaybackPort
  downloads: BrowserDownloadPort | NativeDownloadPort
  settings: SettingsPort
  history: HistoryPort
  programmeCache: ProgrammeCachePort
  windowControls?: WindowControlsPort
  // Register the callback that drains persistence before native exit.
  prepareExit?(prepare: () => Promise<boolean>): Promise<() => void>
  // Release resources owned by the platform adapters.
  dispose(): Promise<void>
}
