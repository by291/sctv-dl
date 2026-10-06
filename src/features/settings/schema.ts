import { z } from 'zod'

import { qualitySchema } from '../programmes/schemas'

export const themeSchema = z.enum(['light', 'dark', 'system'])

export const settingsSchema = z.object({
  quality: qualitySchema.catch('standard'),
  theme: themeSchema.catch('system'),
  favourites: z
    .array(z.unknown())
    .catch([])
    .transform((values) => [
      ...new Set(
        values.filter((value): value is string => typeof value === 'string' && /^\d+$/.test(value)),
      ),
    ]),
})

export type Settings = z.infer<typeof settingsSchema>
