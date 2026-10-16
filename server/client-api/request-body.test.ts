import { IncomingMessage } from 'node:http'
import { Socket } from 'node:net'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { readJson } from './request-body.ts'

afterEach(() => {
  vi.useRealTimers()
})

function jsonRequest(): IncomingMessage {
  const request = new IncomingMessage(new Socket())
  request.headers['content-type'] = 'application/json'

  return request
}

describe('client JSON body reception', () => {
  it.each([
    [16_382, true],
    [16_383, false],
  ])(
    'applies the body byte limit to a JSON string containing %s characters',
    async (length, accepted) => {
      const request = jsonRequest()
      const result = readJson(request, new AbortController().signal)
      const assertion = accepted
        ? expect(result).resolves.toHaveLength(length)
        : expect(result).rejects.toMatchObject({ status: 400 })

      request.push(Buffer.from(JSON.stringify('x'.repeat(length))))
      request.push(null)

      await assertion
      request.destroy()
    },
  )

  it('stops waiting for an unfinished body at its independent reception deadline', async () => {
    vi.useFakeTimers()
    const request = jsonRequest()
    const result = readJson(request, new AbortController().signal)
    const assertion = expect(result).rejects.toMatchObject({ status: 504 })
    let settled = false
    void result.catch(() => {
      settled = true
    })

    await vi.advanceTimersByTimeAsync(19_999)
    expect(settled).toBe(false)
    await vi.advanceTimersByTimeAsync(1)

    await assertion
    request.destroy()
  })

  it('stops waiting for an unfinished body when the caller disconnects', async () => {
    const request = jsonRequest()
    const controller = new AbortController()
    const result = readJson(request, controller.signal)
    const assertion = expect(result).rejects.toMatchObject({ status: 504 })

    controller.abort()

    await assertion
    request.destroy()
  })
})
