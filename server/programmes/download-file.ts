import { resolveVideo } from './video-variants.ts'

import type { ProgrammeContent, Quality } from '../../shared/contracts/programmes.ts'
import type { PreparedDownload } from '../../shared/contracts/downloads.ts'

export function makeDownloadFile(
  content: ProgrammeContent,
  date: string,
  requested: Quality,
): PreparedDownload {
  const variant = resolveVideo(content, requested)

  if (!variant) {
    throw new Error('这条内容没有可下载的视频')
  }

  const { quality, url } = variant
  const filename =
    `${date}_${content.title}_${quality === 'standard' ? '标准' : '流畅'}`
      // Keep filenames valid on Windows and reserve room for the extension.
      // eslint-disable-next-line no-control-regex
      .replace(/[\u0000-\u001f<>:"/\\|?*]/g, '_')
      .slice(0, 150)
      .replace(/[. ]+$/, '') + '.mp4'

  return {
    contentId: content.id,
    title: content.title,
    url,
    filename,
    quality,
  }
}
