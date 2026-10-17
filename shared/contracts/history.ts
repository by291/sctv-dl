import { z } from 'zod'

import { contentRefSchema, urlSchema } from './programmes.ts'

import type { ContentRef } from './programmes.ts'

const milliseconds = z.number().int().nonnegative()

export const historyMetadataSchema = z.object({
  content: contentRefSchema,
  programmeName: z.string(),
  broadcastDate: z.iso.date(),
  title: z.string(),
  cover: urlSchema.nullable(),
})

export const historySampleSchema = z.object({
  positionMs: milliseconds,
  durationMs: milliseconds.nullable(),
  ended: z.boolean(),
  sequence: z.number().int().positive(),
})

export const historyEntrySchema = historyMetadataSchema.extend({
  positionMs: milliseconds,
  durationMs: milliseconds.nullable(),
  viewedAt: z.iso.datetime(),
  completed: z.boolean(),
})

export const historySnapshotSchema = z.object({
  entries: z.array(historyEntrySchema).max(500),
  revision: z.number().int().nonnegative(),
  persisted: z.boolean(),
  warning: z.string().nullable(),
})

export const historySessionSchema = z.object({
  id: z.string().min(1),
  entry: historyEntrySchema.nullable(),
})

export type HistoryMetadata = z.infer<typeof historyMetadataSchema>

export type HistorySample = z.infer<typeof historySampleSchema>

export type HistoryEntry = z.infer<typeof historyEntrySchema>

export type HistorySnapshot = z.infer<typeof historySnapshotSchema>

export type HistorySession = z.infer<typeof historySessionSchema>

export function historyKey(content: ContentRef): string {
  return JSON.stringify([content.programmeId, content.dateId, content.contentId])
}

export function isHistoryCompleted(
  sample: Pick<HistorySample, 'positionMs' | 'durationMs' | 'ended'>,
): boolean {
  return (
    sample.ended ||
    (sample.durationMs !== null &&
      sample.durationMs > 0 &&
      sample.positionMs >= sample.durationMs * 0.95)
  )
}

export function resumePosition(entry: HistoryEntry): number {
  return entry.completed ? 0 : entry.positionMs
}
