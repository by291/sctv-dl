import type { DownloadTask, DownloadActionRequest } from '@shared/contracts/downloads'

export function availableDownloadActions(task: DownloadTask): DownloadActionRequest['action'][] {
  switch (task.state) {
    case 'queued':
    case 'running':
      return ['pause', 'cancel']
    case 'pausing':
    case 'finalizing':
      return []
    case 'paused':
    case 'interrupted':
      return task.canResume ? ['resume', 'restart', 'cancel'] : ['restart', 'cancel']
    case 'failed':
      return [
        ...(task.canResume ? ['resume' as const] : []),
        'restart',
        task.hasPartial ? 'cancel' : 'remove',
      ]
    case 'cancelled':
    case 'missing':
      return ['restart', 'remove']
    case 'completed':
      return task.fileAvailable ? ['openFile', 'revealFile', 'deleteFile', 'remove'] : ['remove']
  }
}

export function isActiveDownload(task: DownloadTask): boolean {
  return ['queued', 'running', 'pausing', 'finalizing'].includes(task.state)
}
