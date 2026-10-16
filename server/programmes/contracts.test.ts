import { describe, expect, it } from 'vitest'

import programmes from '../../shared/fixtures/programmes.json' with { type: 'json' }
import media from '../../shared/fixtures/media-policy.json' with { type: 'json' }
import filenames from '../../shared/fixtures/download-names.json' with { type: 'json' }
import { qualitySchema } from '../../shared/contracts/programmes.ts'
import { createProgrammeApi } from './programme-client.ts'
import { validateMediaTarget } from '../proxy/proxy-policy.ts'
import { makeDownloadFile } from './download-file.ts'

describe('cross-platform contract fixtures', () => {
  it.each(programmes)('normalizes $name', async (fixture) => {
    const client = createProgrammeApi('/api', async () =>
      Response.json({ rs: 200, data: fixture.raw }),
    )
    expect(await client.contents('1', '2')).toEqual(fixture.expected)
  })

  it.each(media)('enforces the media allowlist for $url', (fixture) => {
    if (fixture.allowed) {
      expect(validateMediaTarget(fixture.url).href).toBe(new URL(fixture.url).href)
    } else {
      expect(() => validateMediaTarget(fixture.url)).toThrow()
    }
  })

  it.each(filenames)('uses the actual quality in $filename', (fixture) => {
    const file = makeDownloadFile(
      {
        id: '3',
        title: fixture.title,
        video: fixture.video,
        smoothVideo: fixture.smoothVideo,
        cover: null,
        publishedAt: null,
      },
      fixture.date,
      qualitySchema.parse(fixture.requestedQuality),
    )
    expect(file.filename).toBe(fixture.filename)
    expect(file.quality).toBe(fixture.expectedQuality)
  })
})
