import { describe, expect, it, vi } from 'vitest'
import { ZodError } from 'zod'

import { createProgrammeApi } from '@/features/programmes/api/programme-api'

describe('normalized programme client', () => {
  it('uses the application API and preserves normalized data', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValue(
        Response.json({ data: [{ id: '9007199254740992', name: 'News', cover: null }] }),
      )
    const client = createProgrammeApi('/client-api/v1', fetcher)
    expect(await client.programmes()).toEqual([
      { id: '9007199254740992', name: 'News', cover: null },
    ])
    expect(fetcher).toHaveBeenCalledWith(
      '/client-api/v1/programmes',
      expect.objectContaining({ signal: undefined }),
    )
  })

  it('validates DTOs instead of accepting an upstream response as application data', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValue(Response.json({ data: [{ id: 1, name: 'News', cover: null }] }))
    await expect(createProgrammeApi('/client-api/v1', fetcher).programmes()).rejects.toMatchObject({
      message: expect.stringContaining('数据'),
      cause: expect.any(ZodError),
    })
  })

  it('retains a malformed JSON cause and preserves cancellation while reading the body', async () => {
    const malformed = new SyntaxError('Unexpected token')
    const response = Response.json({})
    vi.spyOn(response, 'json').mockRejectedValue(malformed)
    const fetcher = vi.fn().mockResolvedValue(response)
    const client = createProgrammeApi('/client-api/v1', fetcher)

    await expect(client.programmes()).rejects.toMatchObject({ cause: malformed })

    const aborted = new DOMException('Request stopped', 'AbortError')
    vi.mocked(response.json).mockRejectedValue(aborted)
    await expect(client.programmes()).rejects.toBe(aborted)
  })

  it('rejects invalid IDs and already-cancelled requests before fetching', async () => {
    const fetcher = vi.fn()
    const client = createProgrammeApi('/client-api/v1', fetcher)
    await expect(client.dates('../escape')).rejects.toThrow()
    const controller = new AbortController()
    controller.abort()
    await expect(client.programmes(controller.signal)).rejects.toThrow()
    expect(fetcher).not.toHaveBeenCalled()
  })

  it('propagates server errors and forwards cancellation to the content request', async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValue(
        Response.json({ error: { code: 'upstream', message: '服务错误' } }, { status: 502 }),
      )
    const signal = new AbortController().signal
    await expect(
      createProgrammeApi('/client-api/v1', fetcher).contents('1', '2', signal),
    ).rejects.toThrow('服务错误')
    expect(fetcher).toHaveBeenCalledWith(
      '/client-api/v1/programmes/1/dates/2/contents',
      expect.objectContaining({ signal }),
    )
  })
})
