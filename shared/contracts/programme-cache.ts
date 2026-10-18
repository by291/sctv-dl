import { z } from 'zod'
import {
  idSchema,
  programmeContentSchema,
  programmeDateSchema,
  programmeSchema,
} from './programmes.ts'

export const programmeCacheKeySchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('catalogue') }),
  z.object({ kind: z.literal('dates'), programmeId: idSchema }),
  z.object({ kind: z.literal('contents'), programmeId: idSchema, dateId: idSchema }),
])

// Persisted optional fields may be absent in older snapshots; normalize them before comparison.
const cataloguePayload = z.object({
  kind: z.literal('catalogue'),
  items: z.array(programmeSchema.extend({ cover: programmeSchema.shape.cover.default(null) })),
})
const datesPayload = z.object({
  kind: z.literal('dates'),
  programmeId: idSchema,
  items: z.array(programmeDateSchema),
})
const contentsPayload = z.object({
  kind: z.literal('contents'),
  programmeId: idSchema,
  dateId: idSchema,
  items: z.array(
    programmeContentSchema.extend({
      cover: programmeContentSchema.shape.cover.default(null),
      video: programmeContentSchema.shape.video.default(null),
      smoothVideo: programmeContentSchema.shape.smoothVideo.default(null),
      publishedAt: programmeContentSchema.shape.publishedAt.default(null),
    }),
  ),
})

export const programmeCachePayloadSchema = z.discriminatedUnion('kind', [
  cataloguePayload,
  datesPayload,
  contentsPayload,
])
const snapshotFields = {
  version: z.literal(1),
  revision: z.string().min(1),
  fetchedAt: z.iso.datetime(),
}

export const programmeSnapshotSchema = z.discriminatedUnion('kind', [
  cataloguePayload.extend(snapshotFields),
  datesPayload.extend(snapshotFields),
  contentsPayload.extend(snapshotFields),
])

export const archiveBrowseStateSchema = z.object({
  programmeId: idSchema,
  dateId: idSchema.nullable(),
  date: z.iso.date().nullable(),
  sort: z.enum(['asc', 'desc']),
  scrollY: z.number().finite().nonnegative(),
  visitedAt: z.iso.datetime(),
})

export const cacheReadSchema = z.object({
  epoch: z.string().min(1),
  snapshot: programmeSnapshotSchema.nullable(),
  persisted: z.boolean(),
  warning: z.string().nullable(),
})

export const cacheWriteResultSchema = cacheReadSchema.extend({ accepted: z.boolean() })

export const browseStateReadSchema = z.object({
  epoch: z.string().min(1),
  value: archiveBrowseStateSchema.nullable(),
  persisted: z.boolean(),
  warning: z.string().nullable(),
})

export type ProgrammeCacheKey = z.infer<typeof programmeCacheKeySchema>

export type ProgrammeCachePayload = z.infer<typeof programmeCachePayloadSchema>

export type ProgrammeSnapshot = z.infer<typeof programmeSnapshotSchema>

export type ArchiveBrowseState = z.infer<typeof archiveBrowseStateSchema>

export type CacheRead = z.infer<typeof cacheReadSchema>

export type CacheWriteResult = z.infer<typeof cacheWriteResultSchema>

export type BrowseStateRead = z.infer<typeof browseStateReadSchema>

export function programmeCacheKey(key: ProgrammeCacheKey): string {
  const parsed = programmeCacheKeySchema.parse(key)

  switch (parsed.kind) {
    case 'catalogue':
      return 'catalogue'
    case 'dates':
      return `dates:${parsed.programmeId}`
    case 'contents':
      return `contents:${parsed.programmeId}:${parsed.dateId}`
  }
}
