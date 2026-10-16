import { reportHttpFailure } from '../http-diagnostics.ts'
import { createProgrammeApi } from '../programmes/programme-client.ts'
import { programmeHeaders } from '../proxy/programme-headers.ts'
import { parseClientRoute } from './client-route.ts'
import { describeClientApiError } from './http-errors.ts'
import { createProgrammeService } from './programme-service.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'
import type { ProgrammeApi } from '../programmes/programme-client.ts'
import type { ClientRoute } from './client-route.ts'

function executeRoute(
  route: ClientRoute,
  client: ProgrammeApi,
  signal: AbortSignal,
): Promise<unknown> {
  switch (route.kind) {
    case 'catalogue':
      return client.programmes(signal)
    case 'dates':
      return client.dates(route.programmeId, signal)
    case 'contents':
      return client.contents(route.programmeId, route.dateId, signal)
    case 'playback':
      return createProgrammeService(client, signal).playback(route.input)
    case 'downloads':
      return createProgrammeService(client, signal).downloads(route.input)
  }
}

function reply(
  request: IncomingMessage,
  response: ServerResponse,
  status: number,
  value: unknown,
): void {
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  })
  response.end(request.method === 'HEAD' ? undefined : JSON.stringify(value))
}

export function clientApiMiddleware(
  request: IncomingMessage,
  response: ServerResponse,
  next: () => void,
): void {
  let pathname: string
  try {
    pathname = new URL(request.url || '/', 'http://localhost').pathname
  } catch {
    reply(request, response, 400, { error: { code: 'invalid-input', message: '请求地址无效' } })

    return
  }

  if (pathname !== '/client-api' && !pathname.startsWith('/client-api/')) {
    next()

    return
  }

  const controller = new AbortController()
  const abort = () => controller.abort()
  request.once('aborted', abort)
  response.once('close', abort)

  void (async () => {
    // Validate the route and body before creating an identity or making upstream requests.
    const route = await parseClientRoute(pathname, request, controller.signal)
    const headers = programmeHeaders(request, response, '/client-api')
    const client = createProgrammeApi('https://gw.scgchc.com', fetch, headers)
    const data = await executeRoute(route, client, controller.signal)

    reply(request, response, 200, { data })
  })()
    .catch((cause: unknown) => {
      if (response.destroyed) {
        return
      }

      const failure = describeClientApiError(cause, controller.signal)
      if (failure.status >= 500 && !controller.signal.aborted) {
        reportHttpFailure(request.method, pathname, cause)
      }

      if (failure.allow) {
        response.setHeader('Allow', failure.allow)
      }

      reply(request, response, failure.status, { error: failure.error })
    })
    .finally(() => {
      request.off('aborted', abort)
      response.off('close', abort)
    })
}
