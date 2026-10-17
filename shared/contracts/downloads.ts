import { z } from 'zod'

import { historyMetadataSchema } from './history.ts'

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
  state: z.enum([
    'queued',
    'running',
    'pausing',
    'paused',
    'interrupted',
    'finalizing',
    'completed',
    'failed',
    'cancelled',
    'missing',
  ]),
  attemptId: z.string().min(1),
  createdAt: z.iso.datetime(),
  metadata: historyMetadataSchema,
  canResume: z.boolean(),
  fileAvailable: z.boolean(),
  hasPartial: z.boolean(),
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

export const downloadSnapshotSchema = z.object({
  epoch: z.string().min(1),
  revision: z.number().int().nonnegative(),
  tasks: z.array(downloadTaskSchema),
})

export const downloadEventSchema = z.discriminatedUnion('kind', [
  z.object({
    epoch: z.string().min(1),
    revision: z.number().int().nonnegative(),
    kind: z.literal('upsert'),
    task: downloadTaskSchema,
  }),
  z.object({
    epoch: z.string().min(1),
    revision: z.number().int().nonnegative(),
    kind: z.literal('remove'),
    taskId: z.string().min(1),
  }),
])

export const downloadActionRequestSchema = z.strictObject({
  taskId: z.string().min(1),
  attemptId: z.string().min(1),
  action: z.enum([
    'pause',
    'resume',
    'restart',
    'cancel',
    'remove',
    'deleteFile',
    'openFile',
    'revealFile',
  ]),
})

export const downloadActionResultSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('applied'), task: downloadTaskSchema.nullable() }),
  z.object({ kind: z.literal('skipped'), message: z.string() }),
])

export type DownloadSnapshot = z.infer<typeof downloadSnapshotSchema>

export type DownloadEvent = z.infer<typeof downloadEventSchema>

export type DownloadActionRequest = z.infer<typeof downloadActionRequestSchema>

export type DownloadActionResult = z.infer<typeof downloadActionResultSchema>
