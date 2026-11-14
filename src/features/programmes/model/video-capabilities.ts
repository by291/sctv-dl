import type { ProgrammeContent } from '@/features/programmes/model/programme'

// Check whether the content has a source the current platform can play.
export function hasPlayableVideo(
  content: Pick<ProgrammeContent, 'video' | 'smoothVideo'>,
): boolean {
  return !!(content.video || content.smoothVideo)
}
