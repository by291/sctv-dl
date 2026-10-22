import { createServer } from 'node:http'
import { createReadStream } from 'node:fs'
import { stat } from 'node:fs/promises'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

export function createMediaServer(file) {
  return createServer(async (request, response) => {
    try {
      if (!['GET', 'HEAD'].includes(request.method)) {
        response.writeHead(405).end()

        return
      }

      const mode = new URL(request.url, 'http://localhost').pathname
      if (mode === '/redirect.mp4') {
        response.writeHead(302, { Location: '/probe.mp4' }).end()

        return
      }

      const { size } = await stat(file)
      const match = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range ?? '')
      const start = match ? Number(match[1]) : 0
      const end = match && match[2] ? Math.min(Number(match[2]), size - 1) : size - 1
      if (
        !Number.isSafeInteger(start) ||
        !Number.isSafeInteger(end) ||
        start > end ||
        start >= size
      ) {
        response.writeHead(416, { 'Content-Range': `bytes */${size}` }).end()

        return
      }

      const ignored = mode === '/ignored.mp4'
      const first = ignored ? 0 : start
      const last = ignored ? size - 1 : end
      const headers = {
        'Content-Type': 'video/mp4',
        'Content-Length': last - first + 1,
        'Accept-Ranges': 'bytes',
      }
      if (match && !ignored) {
        headers['Content-Range'] = `bytes ${first}-${last}/${size}`
      }

      response.writeHead(match && !ignored ? 206 : 200, headers)
      if (request.method === 'HEAD') {
        response.end()

        return
      }

      const stream = createReadStream(file, { start: first, end: last, highWaterMark: 16 * 1024 })
      response.on('close', () => stream.destroy())
      stream.on('error', (error) => response.destroy(error))
      if (mode === '/truncated.mp4') {
        stream.once('data', (data) => {
          response.write(data.subarray(0, Math.max(1, Math.floor(data.length / 2))))
          response.destroy()
          stream.destroy()
        })
      } else {
        stream.pipe(response)
      }
    } catch {
      if (!response.headersSent) {
        response.writeHead(500)
      }

      response.end()
    }
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (!process.argv[2]) {
    throw new Error('Pass a local synthetic MP4 path')
  }

  const server = createMediaServer(resolve(process.argv[2]))
  server.listen(0, '127.0.0.1', () =>
    console.log(`http://127.0.0.1:${server.address().port}/probe.mp4`),
  )
}
