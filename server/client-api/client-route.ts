import { downloadRequestSchema } from '../../shared/contracts/downloads.ts'
import { playbackRequestSchema } from '../../shared/contracts/media.ts'
import { idSchema } from '../../shared/contracts/programmes.ts'
import { HttpInputError } from './input-error.ts'
import { readJson } from './request-body.ts'

import type { IncomingMessage } from 'node:http'
import type { DownloadRequest } from '../../shared/contracts/downloads.ts'
import type { PlaybackRequest } from '../../shared/contracts/media.ts'

export type ClientRoute =
  | { kind: 'catalogue' }
  | { kind: 'dates'; programmeId: string }
  | { kind: 'contents'; programmeId: string; dateId: string }
  | { kind: 'playback'; input: PlaybackRequest }
  | { kind: 'downloads'; input: DownloadRequest }

function routeId(value: string | undefined): string {
  const result = idSchema.safeParse(value)
  if (!result.success) {
    throw new HttpInputError('接口 ID 无效')
  }

  return result.data
}

function requireMethod(request: IncomingMessage, methods: string[]): void {
  if (!methods.includes(request.method || '')) {
    throw new HttpInputError('不支持的请求方法', 405, methods.join(', '))
  }
}

export async function parseClientRoute(
  pathname: string,
  request: IncomingMessage,
  signal: AbortSignal,
): Promise<ClientRoute> {
  if (pathname === '/client-api/v1/programmes') {
    requireMethod(request, ['GET', 'HEAD'])

    return { kind: 'catalogue' }
  }

  const dates = pathname.match(/^\/client-api\/v1\/programmes\/([^/]+)\/dates$/)
  if (dates) {
    requireMethod(request, ['GET', 'HEAD'])

    return { kind: 'dates', programmeId: routeId(dates[1]) }
  }

  const contents = pathname.match(
    /^\/client-api\/v1\/programmes\/([^/]+)\/dates\/([^/]+)\/contents$/,
  )
  if (contents) {
    requireMethod(request, ['GET', 'HEAD'])

    return {
      kind: 'contents',
      programmeId: routeId(contents[1]),
      dateId: routeId(contents[2]),
    }
  }

  if (pathname === '/client-api/v1/playback/prepare') {
    requireMethod(request, ['POST'])

    return {
      kind: 'playback',
      input: playbackRequestSchema.parse(await readJson(request, signal)),
    }
  }

  if (pathname === '/client-api/v1/downloads/prepare') {
    requireMethod(request, ['POST'])

    return {
      kind: 'downloads',
      input: downloadRequestSchema.parse(await readJson(request, signal)),
    }
  }

  throw new HttpInputError('不支持的客户端接口', 404)
}
