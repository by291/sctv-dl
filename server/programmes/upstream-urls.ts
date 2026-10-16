function resolveUrl(value: unknown, base: string): string | null {
  if (typeof value !== 'string' || !value.trim()) {
    return null
  }

  try {
    const url = new URL(value.trim(), base)

    return ['https:', 'http:'].includes(url.protocol) ? url.href : null
  } catch {
    return null
  }
}

export const mediaUrl = (value: unknown) => resolveUrl(value, 'https://fscgc.scgchc.com/')

export const imageUrl = (value: unknown) => resolveUrl(value, 'https://kscgc.sctv.com/')
