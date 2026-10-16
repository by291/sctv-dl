export type ProxyTarget =
  { kind: 'programme-api'; url: URL } | { kind: 'media'; url: URL; filename: string | null }

const mediaHosts = new Set(['fscgc.scgchc.com', 'fscgc.sctv-tf.com'])

export function isProxyPath(pathname: string): boolean {
  return pathname === '/media' || pathname === '/api' || pathname.startsWith('/api/')
}

export function resolveProxyTarget(local: URL): ProxyTarget {
  if (local.pathname === '/media') {
    return {
      kind: 'media',
      url: validateMediaTarget(local.searchParams.get('url') || ''),
      filename:
        local.searchParams.get('download') === '1'
          ? local.searchParams.get('filename') || 'programme.mp4'
          : null,
    }
  }

  const path = local.pathname.slice('/api'.length)
  if (
    !local.pathname.startsWith('/api/') ||
    !/^\/app\/v1\/programs(?:\/\d+\/dates(?:\/list|\/\d+\/contents\/list))?$/.test(path)
  ) {
    throw new Error('不支持的节目接口')
  }

  const url = new URL(path, 'https://gw.scgchc.com')
  if (path === '/app/v1/programs') {
    url.search = '?page=0&size=100'
  }

  return { kind: 'programme-api', url }
}

export function validateMediaTarget(raw: string): URL {
  const url = new URL(raw)
  if (
    url.protocol !== 'https:' ||
    !mediaHosts.has(url.hostname) ||
    url.port ||
    url.username ||
    url.password ||
    !url.pathname.toLowerCase().endsWith('.mp4')
  ) {
    throw new Error('暂不支持此视频来源')
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
