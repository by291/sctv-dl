import { describe, expect, it } from 'vitest'

import { validateClientApiEnvironment } from './client-api-config.ts'

describe('client API configuration migration', () => {
  it('keeps default deployments valid and accepts an explicit normalized replacement', () => {
    expect(() => validateClientApiEnvironment(undefined, undefined)).not.toThrow()
    expect(() => validateClientApiEnvironment('/api', undefined)).not.toThrow()
    expect(() =>
      validateClientApiEnvironment('https://old.example/api', 'https://new.example/client-api/v1'),
    ).not.toThrow()
  })

  it('rejects an unmigrated custom raw API instead of sending it normalized requests', () => {
    expect(() => validateClientApiEnvironment('https://old.example/api', undefined)).toThrow(
      'VITE_CLIENT_API_BASE',
    )
  })
})
