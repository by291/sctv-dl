import type { DownloadActionRequest, DownloadTask } from '@shared/contracts/downloads'

type DownloadAction = DownloadActionRequest['action']
interface ActionPresentation {
  label: string
  batchLabel?: string
  confirmation?: { single: string; batch: string; requiresPartial?: boolean }
}

const presentation: Record<DownloadAction, ActionPresentation> = {
  pause: { label: '暂停' },
  resume: { label: '继续下载' },
  restart: {
    label: '重新下载',
    confirmation: {
      single: '从头重新下载？已保存的未完成片段会被删除。',
      batch: '删除未完成片段并从头下载。',
      requiresPartial: true,
    },
  },
  cancel: {
    label: '取消',
    batchLabel: '取消下载',
    confirmation: {
      single: '取消此任务并删除未完成片段？',
      batch: '取消任务并删除未完成片段。',
      requiresPartial: true,
    },
  },
  remove: {
    label: '移除记录',
    confirmation: {
      single: '仅移除此任务记录？已下载文件会保留。',
      batch: '只移除任务记录，已下载文件会保留。',
    },
  },
  deleteFile: {
    label: '删除文件',
    confirmation: {
      single: '删除此下载文件？相关本地播放会停止，任务记录会保留。',
      batch: '删除已下载文件并停止相关本地播放，任务记录会保留。',
    },
  },
  openFile: { label: '外部打开' },
  revealFile: { label: '显示文件' },
}

export const batchDownloadActions: DownloadAction[] = [
  'pause',
  'resume',
  'restart',
  'cancel',
  'remove',
  'deleteFile',
]

export function downloadActionLabel(
  action: DownloadAction,
  scope: 'single' | 'batch' = 'single',
): string {
  const actionPresentation = presentation[action]

  return scope === 'batch'
    ? (actionPresentation.batchLabel ?? actionPresentation.label)
    : actionPresentation.label
}

export function downloadActionConfirmation(
  action: DownloadAction,
  context: { kind: 'single'; task: DownloadTask } | { kind: 'batch'; count: number },
): string | null {
  const confirmation = presentation[action].confirmation
  if (!confirmation) {
    return null
  }

  // Batch actions confirm their possible effects before applicability is rechecked.
  // A single restart/cancel confirms only when this attempt owns partial data.
  if (context.kind === 'batch') {
    return `处理所选 ${context.count} 个任务：${confirmation.batch} 不适用或已变化的任务会跳过。`
  }

  if (confirmation.requiresPartial && !context.task.hasPartial) {
    return null
  }

  return confirmation.single
}
