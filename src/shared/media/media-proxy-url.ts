export function proxyMediaUrl(url: string, filename?: string): string {
  const params = new URLSearchParams({ url })

  if (filename) {
    params.set('download', '1')
    params.set('filename', filename)
  }

  return `${import.meta.env.VITE_MEDIA_BASE || '/media'}?${params}`
}
