import { HttpInputError } from './input-error.ts'

import type { IncomingMessage } from 'node:http'

const MAX_BODY_BYTES = 16_384
const BODY_RECEIVE_TIMEOUT_MS = 20_000

// Read bounded JSON under a body reception deadline and the caller's abort signal.
export async function readJson(request: IncomingMessage, signal: AbortSignal): Promise<unknown> {
  if (!/^application\/json(?:;|$)/i.test(request.headers['content-type'] || '')) {
    throw new HttpInputError('请求必须使用 JSON')
  }

  const raw = await new Promise<string>((resolve, reject) => {
    let receivedBytes = 0
    const chunks: Buffer[] = []

    const abort = () => {
      cleanup()
      reject(new HttpInputError('请求已取消', 504))
    }

    const appendChunk = (chunk: Buffer) => {
      receivedBytes += chunk.length

      // Continue draining oversized bodies, but never retain more than the payload limit.
      if (receivedBytes <= MAX_BODY_BYTES) {
        chunks.push(chunk)
      }
    }

    const error = (cause: Error) => {
      cleanup()
      reject(cause)
    }

    const end = () => {
      cleanup()

      if (receivedBytes > MAX_BODY_BYTES) {
        reject(new HttpInputError('请求内容过大'))
      } else {
        resolve(Buffer.concat(chunks).toString('utf8'))
      }
    }

    const cleanup = () => {
      clearTimeout(bodyDeadline)
      request.off('data', appendChunk)
      request.off('end', end)
      request.off('error', error)
      signal.removeEventListener('abort', abort)
    }

    // Body reception has its own deadline, separate from each upstream header deadline.
    const bodyDeadline = setTimeout(() => {
      cleanup()
      // Discard the remaining body without retaining chunks while the error is sent.
      request.resume()
      reject(new HttpInputError('请求内容接收超时', 504))
    }, BODY_RECEIVE_TIMEOUT_MS)

    request.on('data', appendChunk).once('end', end).once('error', error)
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
