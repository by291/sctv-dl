import { z } from 'zod'

import { imageUrl, mediaUrl } from '@/features/programmes/api/upstream-urls'

// Preserve large IDs as strings; converting an already-rounded number cannot recover its ID.
export const idSchema = z.union([
  z.string().regex(/^\d+$/),
  z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER).transform(String),
])

export const envelopeSchema = z.object({
  rs: z.number(),
  error: z.string().catch('节目服务暂时不可用'),
  data: z.unknown(),
})

export const programmeSchema = z.object({
  id: idSchema,
  name: z.string().catch('未命名栏目'),
  cover: z.unknown().optional().transform(imageUrl),
})

export const programmeDateSchema = z.object({
  id: idSchema,
  date: z.iso.date(),
})

export const programmeContentSchema = z
  .object({
    id: idSchema,
    title: z.string().catch('未命名节目'),
    cover: z.unknown().optional().transform(imageUrl),
    // Upstream omits unavailable variants rather than always returning null.
    video: z.unknown().optional().transform(mediaUrl),
    videoStandard: z.unknown().optional().transform(mediaUrl),
    pubTime: z.string().nullable().catch(null),
  })
  .transform((row) => ({
    id: row.id,
    title: row.title,
    cover: row.cover,
    video: row.video,
    smoothVideo: row.videoStandard,
    publishedAt: row.pubTime,
  }))
