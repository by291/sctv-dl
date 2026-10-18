import { z } from 'zod'

import {
  envelopeSchema,
  idSchema,
  programmeSchema,
  programmeDateSchema,
  programmeContentSchema,
} from './upstream-schemas.ts'

import type {
  Programme,
  ProgrammeContent,
  ProgrammeDate,
} from '../../shared/contracts/programmes.ts'

export class UpstreamError extends Error {}

export class UpstreamTimeoutError extends UpstreamError {}

function parseResponse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value)

  if (result.success) {
    return result.data
  }

  const paths = result.error.issues.map((issue) => issue.path)

  if (paths.some((path) => path.includes('id'))) {
    throw new UpstreamError('接口 ID 无效或超出安全整数范围', { cause: result.error })
  }

  if (paths.some((path) => path.includes('date'))) {
    throw new UpstreamError('接口日期数据格式异常', { cause: result.error })
  }

  throw new UpstreamError('接口数据格式异常', { cause: result.error })
}

function pathId(value: string): string {
  const result = idSchema.safeParse(value)

  if (!result.success) {
    throw new UpstreamError('接口 ID 无效或超出安全整数范围', { cause: result.error })
  }

  return result.data
}

export interface ProgrammeApi {
  programmes(signal?: AbortSignal): Promise<Programme[]>
  dates(programmeId: string, signal?: AbortSignal): Promise<ProgrammeDate[]>
  contents(programmeId: string, dateId: string, signal?: AbortSignal): Promise<ProgrammeContent[]>
}

export function createProgrammeApi(
  base = '/api',
  fetcher: typeof fetch = fetch,
  headers: Record<string, string> = {},
): ProgrammeApi {
  async function request(path: string, signal?: AbortSignal): Promise<unknown> {
    signal?.throwIfAborted()

    const controller = new AbortController()
    let headersTimedOut = false
    const abort = () => controller.abort(signal?.reason)
    signal?.addEventListener('abort', abort, { once: true })

    const headerDeadline = setTimeout(() => {
      headersTimedOut = true
      controller.abort()
    }, 20_000)

    try {
      let response: Response
      try {
        response = await fetcher(`${base.replace(/\/$/, '')}${path}`, {
          signal: controller.signal,
          headers,
          redirect: 'manual',
        })
      } catch (cause) {
        if (headersTimedOut) {
          throw new UpstreamTimeoutError('节目服务响应超时，请稍后重试', { cause })
        }

        throw new UpstreamError('无法连接节目服务，请稍后重试', { cause })
      } finally {
        // This deadline covers headers only; the parent signal still owns disconnect cancellation.
        clearTimeout(headerDeadline)
      }

      if (!response.ok) {
        await response.body?.cancel()
        throw new UpstreamError(`请求失败（HTTP ${response.status}），请稍后重试`)
      }

      let raw: unknown
      try {
        raw = await response.json()
      } catch (cause) {
        throw new UpstreamError('接口数据不是有效 JSON，请检查代理服务', { cause })
      }

      const envelope = parseResponse(envelopeSchema, raw)
      if (envelope.rs !== 200) {
        throw new UpstreamError(envelope.error)
      }

      return envelope.data
    } finally {
      clearTimeout(headerDeadline)
      signal?.removeEventListener('abort', abort)
    }
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
