export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : '连接失败，请检查网络后重试'
}
