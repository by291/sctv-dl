import { describe, expect, it } from 'vitest'
import { LatestRequest } from '@/shared/utils/latest-request'

describe('selection request races', () => {
  it('aborts the previous request and prevents late responses from committing', () => {
    const latest = new LatestRequest()
    const first = latest.begin()
    const second = latest.begin()
    expect(first.signal.aborted).toBe(true)
    expect(first.isCurrent()).toBe(false)
    expect(second.isCurrent()).toBe(true)
    latest.cancel()
    expect(second.isCurrent()).toBe(false)
  })
})
