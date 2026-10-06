import { describe, expect, it } from 'vitest'
import { settingsSchema } from './schema'

describe('settings validation', () => {
  it('recovers damaged fields without discarding valid preferences', () => {
    expect(
      settingsSchema.parse({
        quality: 'invalid',
        theme: 'dark',
        favourites: ['1', 2, null, 'abc'],
      }),
    ).toEqual({ quality: 'standard', theme: 'dark', favourites: ['1'] })
  })

  it('supplies defaults when old storage has no preferences', () => {
    expect(settingsSchema.parse({})).toEqual({
      quality: 'standard',
      theme: 'light',
      favourites: [],
    })
  })
})
