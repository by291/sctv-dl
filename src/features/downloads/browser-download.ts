import { proxyMediaUrl } from '../../shared/media'

import type { DownloadTask } from './schema'

export async function handOffDownload(task: DownloadTask): Promise<void> {
  const url = proxyMediaUrl(task.url, task.filename)
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
  link.download = task.filename
  link.hidden = true
  document.body.append(link)
  link.click()
  link.remove()
}
