import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'

export interface VideoVariant {
  quality: Quality
  url: string
}

export function getVideoVariants(content: ProgrammeContent): VideoVariant[] {
  const variants: VideoVariant[] = []

  if (content.video) {
    variants.push({ quality: 'standard', url: content.video })
  }

  // Some broadcasts use the same file for both fields; switching it adds no alternative.
  if (content.smoothVideo && content.smoothVideo !== content.video) {
    variants.push({ quality: 'smooth', url: content.smoothVideo })
  }

  return variants
}

export function resolveVideo(content: ProgrammeContent, requested: Quality): VideoVariant | null {
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
