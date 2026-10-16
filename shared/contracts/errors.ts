import { z } from 'zod'

export const applicationErrorSchema = z.object({
  code: z.enum(['invalid-input', 'not-found', 'upstream', 'timeout', 'cancelled', 'storage']),
  message: z.string(),
})

export type ApplicationError = z.infer<typeof applicationErrorSchema>
