import { proxyMediaUrl } from '@/shared/media/media-proxy-url'

export async function handOffDownload(file: { url: string; filename: string }): Promise<void> {
  const url = proxyMediaUrl(file.url, file.filename)
  const response = await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(25_000) })

  if (!response.ok) {
    throw new Error(`视频暂时无法访问（HTTP ${response.status}）`)
  }

  if (
    !/^attachment(?:;|$)/i.test(response.headers.get('content-disposition') || '') ||
    !/^(video\/|application\/octet-stream)/i.test(response.headers.get('content-type') || '')
  ) {
    throw new Error('下载代理未返回视频，请检查服务配置')
  }

  // Let the browser stream the download instead of buffering the entire MP4 in a Blob.
  const link = document.createElement('a')
  link.href = url
  link.download = file.filename
  link.hidden = true
  document.body.append(link)
  link.click()
  link.remove()
}
