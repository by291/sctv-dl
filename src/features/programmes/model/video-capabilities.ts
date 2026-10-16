import type { ProgrammeContent } from '@/features/programmes/model/programme'

export function hasPlayableVideo(
  content: Pick<ProgrammeContent, 'video' | 'smoothVideo'>,
): boolean {
  return !!(content.video || content.smoothVideo)
}
