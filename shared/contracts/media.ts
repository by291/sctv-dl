import { z } from 'zod'

import { contentRefSchema, qualitySchema } from './programmes.ts'

export const playbackRequestSchema = contentRefSchema.extend({ quality: qualitySchema })

export const playbackSessionSchema = z.object({
  id: z.string().min(1),
  selectedQuality: qualitySchema,
  // Native sessions may use a custom protocol instead of an HTTP URL.
  sources: z.array(z.object({ quality: qualitySchema, url: z.string().min(1) })).min(1),
})

export type PlaybackRequest = z.infer<typeof playbackRequestSchema>

export type PlaybackSession = z.infer<typeof playbackSessionSchema>
