import { HttpInputError } from './http-errors.ts'

import type { IncomingMessage } from 'node:http'

export async function readJson(request: IncomingMessage, signal: AbortSignal): Promise<unknown> {
  if (!/^application\/json(?:;|$)/i.test(request.headers['content-type'] || '')) {
    throw new HttpInputError('请求必须使用 JSON')
  }

  const raw = await new Promise<string>((resolve, reject) => {
    let length = 0
    const chunks: Buffer[] = []

    const abort = () => {
      cleanup()
      reject(new HttpInputError('请求已取消', 504))
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
        reject(new HttpInputError('请求内容过大'))
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

    // Body reception has its own deadline, separate from each upstream header deadline.
    const bodyTimer = setTimeout(() => {
      cleanup()
      request.resume()
      reject(new HttpInputError('请求内容接收超时', 504))
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
    throw new HttpInputError('请求不是有效 JSON')
  }
}
