import { z } from 'zod'

export const idSchema = z.string().regex(/^\d+$/)

export const qualitySchema = z.enum(['standard', 'smooth'])

export const urlSchema = z.url().refine((value) => /^https?:\/\//.test(value))

export const programmeSchema = z.object({
  id: idSchema,
  name: z.string(),
  cover: urlSchema.nullable(),
})

export const programmeDateSchema = z.object({ id: idSchema, date: z.iso.date() })

export const programmeContentSchema = z.object({
  id: idSchema,
  title: z.string(),
  cover: urlSchema.nullable(),
  video: urlSchema.nullable(),
  smoothVideo: urlSchema.nullable(),
  publishedAt: z.string().nullable(),
})

export const contentRefSchema = z.strictObject({
  programmeId: idSchema,
  dateId: idSchema,
  contentId: idSchema,
})

export type Quality = z.infer<typeof qualitySchema>

export type Programme = z.infer<typeof programmeSchema>

export type ProgrammeDate = z.infer<typeof programmeDateSchema>

export type ProgrammeContent = z.infer<typeof programmeContentSchema>

export type ContentRef = z.infer<typeof contentRefSchema>
