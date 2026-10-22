import assert from 'node:assert/strict'
import { mkdtemp, writeFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import test from 'node:test'
import { createMediaServer } from './media-server.mjs'

test('serves bounded ranges and rejects unsatisfiable requests', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'sctv-media-'))
  const file = join(directory, 'probe.mp4')
  await writeFile(file, Buffer.from([0, 1, 2, 3, 4, 5]))
  const server = createMediaServer(file)
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  try {
    const base = `http://127.0.0.1:${server.address().port}`
    const partial = await fetch(`${base}/probe.mp4`, { headers: { Range: 'bytes=2-4' } })
    assert.equal(partial.status, 206)
    assert.equal(partial.headers.get('Content-Range'), 'bytes 2-4/6')
    assert.deepEqual([...new Uint8Array(await partial.arrayBuffer())], [2, 3, 4])
    assert.equal(
      (await fetch(`${base}/probe.mp4`, { headers: { Range: 'bytes=9-10' } })).status,
      416,
    )
    const head = await fetch(`${base}/probe.mp4`, { method: 'HEAD' })
    assert.equal(head.headers.get('Content-Length'), '6')
    assert.equal((await head.arrayBuffer()).byteLength, 0)
  } finally {
    server.closeAllConnections()
    await new Promise((resolve) => server.close(resolve))
    await rm(directory, { recursive: true, force: true })
  }
})
