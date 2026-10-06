export function validateMediaTarget(raw: string): URL {
  const url = new URL(raw)
  if (
    url.protocol !== 'https:' ||
    url.hostname !== 'fscgc.scgchc.com' ||
    url.port ||
    url.username ||
    url.password ||
    !url.pathname.toLowerCase().endsWith('.mp4')
  ) {
    throw new Error('仅支持已验证的视频 CDN MP4 地址')
  }

  return url
}

export function contentDisposition(filename: string): string {
  // Filenames must not contain control characters or header delimiters.
  const safe =
    // eslint-disable-next-line no-control-regex
    filename.replace(/[\r\n\u0000-\u001f<>:"/\\|?*]/g, '_').slice(0, 180) || 'programme.mp4'
  const encoded = encodeURIComponent(safe).replace(
    /['()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  )

  return `attachment; filename="programme.mp4"; filename*=UTF-8''${encoded}`
}
