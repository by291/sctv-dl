interface ProgrammeServiceInput {
  error: string
  refreshError: string
  refreshing: boolean
  cached: boolean
  fetchedAt: string | null
}

export type ProgrammeServiceStatus =
  | { kind: 'unavailable' | 'refresh-failed'; label: string; error: string }
  | { kind: 'checking' | 'refreshing' | 'cached' | 'ready'; label: string; error: null }

export function programmeServiceStatus(input: ProgrammeServiceInput): ProgrammeServiceStatus {
  if (input.error) {
    return { kind: 'unavailable', label: '连接暂时不可用', error: input.error }
  }

  if (input.refreshError) {
    return {
      kind: 'refresh-failed',
      label: '刷新失败，显示已保存数据',
      error: input.refreshError,
    }
  }

  // A saved timestamp establishes usable data, not a successful live connection.
  if (input.refreshing) {
    return {
      kind: input.fetchedAt ? 'refreshing' : 'checking',
      label: input.cached
        ? '正在刷新，显示节目缓存'
        : input.fetchedAt
          ? '正在刷新节目数据'
          : '正在检查节目服务',
      error: null,
    }
  }

  if (input.cached) {
    return { kind: 'cached', label: '正在显示节目缓存', error: null }
  }

  return input.fetchedAt
    ? { kind: 'ready', label: '已连接节目服务', error: null }
    : { kind: 'checking', label: '正在检查节目服务', error: null }
}
