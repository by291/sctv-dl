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

// Resolve upstream video paths against the media origin.
export const mediaUrl = (value: unknown) => resolveUrl(value, 'https://fscgc.scgchc.com/')

// Resolve upstream image paths against the cover origin.
export const imageUrl = (value: unknown) => resolveUrl(value, 'https://kscgc.sctv.com/')
