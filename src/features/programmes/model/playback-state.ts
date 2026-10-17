import type { HistoryMetadata } from '@shared/contracts/history'
import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'

export interface PlaybackSnapshot {
  positionMs: number
  durationMs: number | null
  speed: number
  quality: Quality
  playing: boolean
  ended: boolean
  initialized: boolean
}

export type PlaybackRestore = Pick<PlaybackSnapshot, 'positionMs' | 'speed' | 'playing'>

export type PlaybackSampleReason = 'progress' | 'seek' | 'pause' | 'ended' | 'state'

export type PreviewInput = { metadata: HistoryMetadata; content: ProgrammeContent } & (
  { kind: 'online' } | { kind: 'download'; taskId: string }
)
