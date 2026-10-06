import type { z } from 'zod'
import type {
  programmeSchema,
  programmeDateSchema,
  programmeContentSchema,
  qualitySchema,
} from './schemas'

export type Programme = z.infer<typeof programmeSchema>

export type ProgrammeDate = z.infer<typeof programmeDateSchema>

export type ProgrammeContent = z.infer<typeof programmeContentSchema>

export type Quality = z.infer<typeof qualitySchema>
