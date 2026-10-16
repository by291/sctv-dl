import { expect, it, vi } from 'vitest'

import { createWebPlayback } from '@/features/programmes/api/playback.web'

it('adapts backend-selected playback sources to the media proxy without changing quality', async () => {
  const fetcher = vi.fn().mockResolvedValue(
    Response.json({
      data: {
        id: 'session-1',
        selectedQuality: 'smooth',
        sources: [{ quality: 'smooth', url: 'https://fscgc.scgchc.com/smooth.mp4' }],
      },
    }),
  )
  const port = createWebPlayback('/client-api/v1', fetcher)
  const session = await port.open({
    programmeId: '1',
    dateId: '2',
    contentId: '3',
    quality: 'standard',
  })
  expect(session.selectedQuality).toBe('smooth')
  expect(session.sources).toEqual([
    { quality: 'smooth', url: '/media?url=https%3A%2F%2Ffscgc.scgchc.com%2Fsmooth.mp4' },
  ])
  expect(fetcher).toHaveBeenCalledWith(
    '/client-api/v1/playback/prepare',
    expect.objectContaining({
      method: 'POST',
      body: '{"programmeId":"1","dateId":"2","contentId":"3","quality":"standard"}',
    }),
  )
  await port.close(session.id)
  expect(fetcher).toHaveBeenCalledTimes(1)
})
