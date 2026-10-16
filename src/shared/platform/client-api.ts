import { z } from 'zod'

import { applicationErrorSchema } from '@shared/contracts/errors'

export function createClientApi(base = '/client-api/v1', fetcher: typeof fetch = fetch) {
  return async function request<T>(
    path: string,
    schema: z.ZodType<T>,
    options: { signal?: AbortSignal; body?: unknown } = {},
  ): Promise<T> {
    options.signal?.throwIfAborted()
    const response = await fetcher(`${base.replace(/\/$/, '')}${path}`, {
      signal: options.signal,
      ...(options.body === undefined
        ? {}
        : {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(options.body),
          }),
    })
    let raw: unknown
    try {
      raw = await response.json()
    } catch {
      throw new Error(`接口未返回有效 JSON（HTTP ${response.status}），请检查服务配置`)
    }

    if (!response.ok) {
      const error = z.object({ error: applicationErrorSchema }).safeParse(raw)
      throw new Error(
        error.success ? error.data.error.message : `请求失败（HTTP ${response.status}）`,
      )
    }

    const result = z.object({ data: schema }).safeParse(raw)
    if (!result.success) {
      throw new Error('接口数据格式异常，请检查客户端与服务版本')
    }

    return result.data.data
  }
}
