import { z } from 'zod'

import { contentRefSchema, idSchema, qualitySchema, urlSchema } from './programmes.ts'

export const downloadRequestSchema = z.strictObject({
  programmeId: idSchema,
  dateId: idSchema,
  contentIds: z
    .array(idSchema)
    .min(1)
    .transform((ids) => [...new Set(ids)])
    .pipe(z.array(idSchema).max(100)),
  quality: qualitySchema,
})

export const fileFailureSchema = z.object({ contentId: idSchema, message: z.string() })

export const preparedDownloadSchema = z.object({
  contentId: idSchema,
  title: z.string(),
  url: urlSchema,
  filename: z.string().min(1),
  quality: qualitySchema,
})

export const preparedDownloadsSchema = z.object({
  files: z.array(preparedDownloadSchema),
  failures: z.array(fileFailureSchema),
  usedFallback: z.boolean(),
})

export const downloadTaskSchema = z.object({
  id: z.string().min(1),
  content: contentRefSchema,
  filename: z.string().min(1),
  quality: qualitySchema,
  state: z.enum(['queued', 'running', 'completed', 'failed', 'cancelled']),
  receivedBytes: z.number().int().nonnegative(),
  totalBytes: z.number().int().nonnegative().nullable(),
  error: z.string().nullable(),
  revision: z.number().int().nonnegative(),
})

export type DownloadRequest = z.infer<typeof downloadRequestSchema>

export type PreparedDownload = z.infer<typeof preparedDownloadSchema>

export type PreparedDownloads = z.infer<typeof preparedDownloadsSchema>

export type FileFailure = z.infer<typeof fileFailureSchema>

export type DownloadTask = z.infer<typeof downloadTaskSchema>

export type DownloadStartResult =
  | { kind: 'cancelled' }
  | { kind: 'browser'; handedOff: number; usedFallback: boolean; failures: FileFailure[] }
  | { kind: 'native'; taskIds: string[]; usedFallback: boolean; failures: FileFailure[] }
