import { resolveVideo } from '../programmes/video'

import type { ProgrammeContent, Quality } from '../programmes/types'
import type { DownloadTask } from './schema'

export type { DownloadTask } from './schema'

export function makeDownloadTask(
  content: ProgrammeContent,
  programme: string,
  date: string,
  requested: Quality,
): DownloadTask {
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
    id: `${content.id}:${quality}`,
    contentId: content.id,
    title: content.title,
    programme,
    date,
    url,
    filename,
    quality,
    status: 'queued',
    createdAt: new Date().toISOString(),
  }
}

export function appendTasks(existing: DownloadTask[], added: DownloadTask[]): DownloadTask[] {
  const ids = new Set(existing.map((task) => task.id))

  return [
    ...existing,
    ...added.filter((task) => {
      if (ids.has(task.id)) {
        return false
      }

      ids.add(task.id)

      return true
    }),
  ]
}

export function recoverInterruptedTasks(tasks: DownloadTask[]): DownloadTask[] {
  return tasks.map((task) => ({
    ...task,
    status: task.status === 'checking' ? 'queued' : task.status,
  }))
}
