import { resolveVideo } from '@/features/programmes/model/video-variants'

import type { ProgrammeContent } from '@/features/programmes/model/programme'
import type { Quality } from '@/shared/media/video-quality'

export interface DownloadFile {
  contentId: string
  title: string
  url: string
  filename: string
  quality: Quality
}

export function makeDownloadFile(
  content: ProgrammeContent,
  date: string,
  requested: Quality,
): DownloadFile {
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
