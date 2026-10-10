import { z } from 'zod'

export const qualitySchema = z.enum(['standard', 'smooth'])

export type Quality = z.infer<typeof qualitySchema>
