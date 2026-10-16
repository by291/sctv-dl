import { z } from 'zod'

import { downloadRequestSchema } from '../../shared/contracts/downloads.ts'
import { playbackRequestSchema } from '../../shared/contracts/media.ts'
import {
  createProgrammeApi,
  UpstreamError,
  UpstreamTimeoutError,
} from '../programmes/programme-client.ts'
import { programmeHeaders } from '../proxy/programme-headers.ts'
import { ClientApiError, createProgrammeService } from './programme-service.ts'

import type { IncomingMessage, ServerResponse } from 'node:http'

async function readJson(request: IncomingMessage, signal: AbortSignal): Promise<unknown> {
  if (!/^application\/json(?:;|$)/i.test(request.headers['content-type'] || '')) {
    throw new ClientApiError('请求必须使用 JSON')
  }

  const raw = await new Promise<string>((resolve, reject) => {
    let length = 0
    const chunks: Buffer[] = []
    const abort = () => {
      cleanup()
      reject(new ClientApiError('请求已取消', 504))
    }

    const data = (chunk: Buffer) => {
      length += chunk.length
      if (length <= 16_384) {
        chunks.push(chunk)
      }
    }

    const error = (cause: Error) => {
      cleanup()
      reject(cause)
    }

    const end = () => {
      cleanup()
      if (length > 16_384) {
        reject(new ClientApiError('请求内容过大'))
      } else {
        resolve(Buffer.concat(chunks).toString('utf8'))
      }
    }

    const cleanup = () => {
      clearTimeout(bodyTimer)
      request.off('data', data)
      request.off('end', end)
      request.off('error', error)
      signal.removeEventListener('abort', abort)
    }

    const bodyTimer = setTimeout(() => {
      cleanup()
      request.resume()
      reject(new ClientApiError('请求内容接收超时', 504))
    }, 20_000)
    request.on('data', data).once('end', end).once('error', error)
    signal.addEventListener('abort', abort, { once: true })
    if (signal.aborted) {
      abort()
    }
  })

  try {
    return JSON.parse(raw) as unknown
  } catch {
    throw new ClientApiError('请求不是有效 JSON')
  }
}

function reply(request: IncomingMessage, response: ServerResponse, status: number, value: unknown) {
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
  let path: string
  try {
    path = new URL(request.url || '/', 'http://localhost').pathname
  } catch {
    reply(request, response, 400, { error: { code: 'invalid-input', message: '请求地址无效' } })

    return
  }

  if (path !== '/client-api' && !path.startsWith('/client-api/')) {
    next()

    return
  }

  const controller = new AbortController()
  const abort = () => controller.abort()
  request.once('aborted', abort)
  response.once('close', abort)

  void (async () => {
    const catalogue = path === '/client-api/v1/programmes'
    const dates = path.match(/^\/client-api\/v1\/programmes\/([^/]+)\/dates$/)
    const contents = path.match(/^\/client-api\/v1\/programmes\/([^/]+)\/dates\/([^/]+)\/contents$/)
    const preparation =
      path === '/client-api/v1/playback/prepare' || path === '/client-api/v1/downloads/prepare'
    if (!catalogue && !dates && !contents && !preparation) {
      throw new ClientApiError('不支持的客户端接口', 404)
    }

    const methods = preparation ? ['POST'] : ['GET', 'HEAD']
    if (!methods.includes(request.method || '')) {
      response.setHeader('Allow', methods.join(', '))
      throw new ClientApiError('不支持的请求方法', 405)
    }

    if (
      (dates && !/^\d+$/.test(dates[1]!)) ||
      (contents && (!/^\d+$/.test(contents[1]!) || !/^\d+$/.test(contents[2]!)))
    ) {
      throw new ClientApiError('接口 ID 无效')
    }

    const body = preparation ? await readJson(request, controller.signal) : undefined
    // Validate before any upstream request or caller-controlled target is resolved.
    const parsed = preparation
      ? path.endsWith('/downloads/prepare')
        ? downloadRequestSchema.parse(body)
        : playbackRequestSchema.parse(body)
      : null
    const headers = programmeHeaders(request, response, '/client-api')
    const client = createProgrammeApi('https://gw.scgchc.com', fetch, headers)
    const service = createProgrammeService(client, controller.signal)
    let data: unknown
    if (catalogue) {
      data = await client.programmes(controller.signal)
    } else if (contents) {
      data = await client.contents(contents[1]!, contents[2]!, controller.signal)
    } else if (dates) {
      data = await client.dates(dates[1]!, controller.signal)
    } else if (parsed && 'contentIds' in parsed) {
      data = await service.downloads(parsed)
    } else if (parsed) {
      data = await service.playback(parsed)
    }

    reply(request, response, 200, { data })
  })()
    .catch((cause: unknown) => {
      if (response.destroyed) {
        return
      }

      const status =
        controller.signal.aborted || cause instanceof UpstreamTimeoutError
          ? 504
          : cause instanceof ClientApiError
            ? cause.status
            : cause instanceof z.ZodError
              ? 400
              : cause instanceof UpstreamError
                ? 502
                : 500
      const code =
        status === 504
          ? 'timeout'
          : status === 404
            ? 'not-found'
            : status < 500
              ? 'invalid-input'
              : 'upstream'
      const message =
        status === 504
          ? '节目服务请求超时，请稍后重试'
          : cause instanceof z.ZodError
            ? '请求参数无效'
            : cause instanceof Error && status !== 500
              ? cause.message
              : '节目服务暂不可用'
      reply(request, response, status, { error: { code, message } })
    })
    .finally(() => {
      request.off('aborted', abort)
      response.off('close', abort)
    })
}
