import { describe, expect, it } from 'vitest'

import { UpstreamError, UpstreamTimeoutError } from '../programmes/programme-client.ts'
import { describeClientApiError } from './http-errors.ts'
import { HttpInputError } from './input-error.ts'

describe('client API error responses', () => {
  it.each([new Error('Private implementation detail'), { private: 'detail' }, undefined])(
    'conceals unexpected failures while retaining an internal server status',
    (cause) => {
      const failure = describeClientApiError(cause, new AbortController().signal)

      expect(failure.status).toBe(500)
      expect(failure.error.code).toBe('upstream')
      expect(JSON.stringify(failure)).not.toMatch(/private|implementation|detail/i)
    },
  )

  it('keeps the response deadline distinct from a failed upstream connection', () => {
    const signal = new AbortController().signal

    expect(describeClientApiError(new UpstreamError('Connection failed'), signal)).toMatchObject({
      status: 502,
      error: { code: 'upstream' },
    })
    expect(describeClientApiError(new UpstreamTimeoutError('Timed out'), signal)).toMatchObject({
      status: 504,
      error: { code: 'timeout' },
    })
    expect(describeClientApiError(new HttpInputError('Body timed out', 504), signal)).toMatchObject(
      {
        status: 504,
        error: { code: 'timeout' },
      },
    )
  })

  it('keeps the cancellation response contract when an aborted upstream request rejects', () => {
    const controller = new AbortController()
    controller.abort()

    const failure = describeClientApiError(
      new UpstreamError('Connection failed'),
      controller.signal,
    )

    expect(failure).toMatchObject({ status: 504, error: { code: 'timeout' } })
  })
})
