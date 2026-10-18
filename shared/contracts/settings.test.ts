import { describe, expect, it } from 'vitest'

import { settingsSchema } from './settings.ts'
import settings from '../fixtures/settings.json' with { type: 'json' }

describe('persisted settings compatibility', () => {
  it.each(settings)('retains preference defaults and valid favourite IDs', (fixture) => {
    expect(settingsSchema.parse(fixture.raw)).toEqual(fixture.expected)
  })
})
