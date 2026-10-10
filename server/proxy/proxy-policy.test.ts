import { describe, expect, it } from 'vitest'
import { validateMediaTarget, contentDisposition } from './proxy-policy.ts'

describe('media proxy boundary', () => {
  it('accepts only HTTPS MP4 files on the verified CDN', () => {
    expect(validateMediaTarget('https://fscgc.scgchc.com/NewsMedia/1.mp4').hostname).toBe(
      'fscgc.scgchc.com',
    )
    for (const target of [
      'http://fscgc.scgchc.com/1.mp4',
      'https://evil.example/1.mp4',
      'https://fscgc.scgchc.com.evil.example/a.mp4',
      'https://user@fscgc.scgchc.com/a.mp4',
      'https://fscgc.scgchc.com:444/a.mp4',
      'https://fscgc.scgchc.com/a.html',
    ]) {
      expect(() => validateMediaTarget(target)).toThrow()
    }
  })
  it('encodes filenames without letting them inject headers', () => {
    const value = contentDisposition('节目\r\nX-Test: 1.mp4')
    expect(value).not.toMatch(/[\r\n]/)
    expect(value).toContain("filename*=UTF-8''")
  })
})
