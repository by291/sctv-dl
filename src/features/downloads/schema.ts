import { z } from 'zod'

import { qualitySchema } from '../programmes/schemas'

const downloadUrlSchema = z.url().refine((raw) => {
  const url = new URL(raw)

  return (
    url.protocol === 'https:' &&
    url.hostname === 'fscgc.scgchc.com' &&
    !url.port &&
    !url.username &&
    !url.password &&
    url.pathname.toLowerCase().endsWith('.mp4')
  )
})

export const downloadTaskSchema = z.object({
  id: z.string(),
  contentId: z.string(),
  title: z.string(),
  programme: z.string(),
  date: z.string(),
  url: downloadUrlSchema,
  filename: z.string(),
  quality: qualitySchema,
  status: z.enum(['queued', 'checking', 'handed-off', 'failed']),
  createdAt: z.string(),
  error: z.string().optional(),
})

// Discard invalid records individually; never silently truncate valid tasks on reload.
export const downloadTasksSchema = z
  .array(z.unknown())
  .catch([])
  .transform((values) =>
    values.flatMap((value) => {
      const result = downloadTaskSchema.safeParse(value)

      return result.success ? [result.data] : []
    }),
  )

export type DownloadTask = z.infer<typeof downloadTaskSchema>
