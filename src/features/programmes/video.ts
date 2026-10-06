import type { ProgrammeContent, Quality } from './types'

export function resolveVideo(
  content: ProgrammeContent,
  requested: Quality,
): { quality: Quality; url: string } | null {
  if (requested === 'smooth' && content.smoothVideo) {
    return { quality: 'smooth', url: content.smoothVideo }
  }

  if (content.video) {
    return { quality: 'standard', url: content.video }
  }

  if (content.smoothVideo) {
    return { quality: 'smooth', url: content.smoothVideo }
  }

  return null
}
