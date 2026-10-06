import { z } from 'zod'

import {
  envelopeSchema,
  idSchema,
  programmeSchema,
  programmeDateSchema,
  programmeContentSchema,
} from './schemas'

import type { Programme, ProgrammeContent, ProgrammeDate } from './types'

function parseResponse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value)

  if (result.success) {
    return result.data
  }

  const paths = result.error.issues.map((issue) => issue.path)

  if (paths.some((path) => path.includes('id'))) {
    throw new Error('接口 ID 无效或超出安全整数范围')
  }

  if (paths.some((path) => path.includes('date'))) {
    throw new Error('接口日期数据格式异常')
  }

  throw new Error('接口数据格式异常')
}

function pathId(value: string): string {
  const result = idSchema.safeParse(value)

  if (!result.success) {
    throw new Error('接口 ID 无效或超出安全整数范围')
  }

  return result.data
}

export function createApi(base = '/api', fetcher: typeof fetch = fetch) {
  async function request(path: string, signal?: AbortSignal): Promise<unknown> {
    const response = await fetcher(`${base.replace(/\/$/, '')}${path}`, { signal })

    if (!response.ok) {
      throw new Error(`请求失败（HTTP ${response.status}），请稍后重试`)
    }

    let raw: unknown

    try {
      raw = await response.json()
    } catch {
      throw new Error('接口数据不是有效 JSON，请检查代理服务')
    }

    const envelope = parseResponse(envelopeSchema, raw)

    if (envelope.rs !== 200) {
      throw new Error(envelope.error)
    }

    return envelope.data
  }

  return {
    async programmes(signal?: AbortSignal): Promise<Programme[]> {
      const schema = z.object({ records: z.array(programmeSchema) })
      const data = parseResponse(schema, await request('/app/v1/programs?page=0&size=100', signal))

      return data.records
    },

    async dates(programmeId: string, signal?: AbortSignal): Promise<ProgrammeDate[]> {
      const rows = parseResponse(
        z.array(programmeDateSchema),
        await request(`/app/v1/programs/${pathId(programmeId)}/dates/list`, signal),
      )

      // Deduplicate broadcast dates, retaining the last upstream record for each date.
      return [...new Map(rows.map((row) => [row.date, row])).values()].sort((a, b) =>
        b.date.localeCompare(a.date),
      )
    },

    async contents(
      programmeId: string,
      dateId: string,
      signal?: AbortSignal,
    ): Promise<ProgrammeContent[]> {
      return parseResponse(
        z.array(programmeContentSchema),
        await request(
          `/app/v1/programs/${pathId(programmeId)}/dates/${pathId(dateId)}/contents/list`,
          signal,
        ),
      )
    },
  }
}

export const api = createApi(import.meta.env.VITE_API_BASE || '/api')

export type ProgrammeApi = ReturnType<typeof createApi>
