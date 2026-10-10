import { createServer } from 'node:http'
import { fileURLToPath } from 'node:url'

import { createHttpApp } from './http-app.ts'

const host = process.env.HOST || '0.0.0.0'
const port = Number(process.env.PORT || '3000')

if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error('PORT must be an integer between 1 and 65535.')
}

const assetsDirectory = fileURLToPath(new URL('../dist', import.meta.url))
const server = createServer(createHttpApp(assetsDirectory))

server.on('error', (error) => {
  console.error('Unable to start sctv-dl:', error.message)
  process.exitCode = 1
})

server.listen(port, host, () => {
  console.info(`sctv-dl listening on http://${host}:${port}`)
})

let stopping = false

function shutdown(): void {
  if (stopping) {
    return
  }

  stopping = true
  console.info('Stopping sctv-dl; active transfers have up to 30 seconds to finish.')
  const deadline = setTimeout(() => server.closeAllConnections(), 30_000)
  deadline.unref()
  server.close(() => clearTimeout(deadline))
}

process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)
