import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { once } from 'node:events'
import { join, relative, sep } from 'node:path'
import { createServer } from 'vite'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import config from '../vite.config.ts'

import type { ViteDevServer } from 'vite'

let directory: string
let server: ViteDevServer | undefined

beforeEach(async () => {
  directory = await realpath(await mkdtemp(join(tmpdir(), 'sctv-vite-startup-')))
  const reportDirectories = [
    join(directory, 'android/app/build/reports'),
    join(directory, 'src-tauri/target/reports'),
  ]

  await mkdir(join(directory, 'src'))
  await writeFile(
    join(directory, 'index.html'),
    '<script type="module" src="/src/main.js"></script>',
  )
  await writeFile(join(directory, 'src/main.js'), "export { value } from 'web-fixture-dep'")
  for (const [index, reportDirectory] of reportDirectories.entries()) {
    await mkdir(reportDirectory, { recursive: true })
    await writeFile(
      join(reportDirectory, 'index.html'),
      `<script type="module">import "native-fixture-dep-${index}"</script>`,
    )
  }

  for (const name of ['web-fixture-dep', 'native-fixture-dep-0', 'native-fixture-dep-1']) {
    const packageDirectory = join(directory, 'node_modules', name)

    await mkdir(packageDirectory, { recursive: true })
    await writeFile(
      join(packageDirectory, 'package.json'),
      JSON.stringify({ name, type: 'module', exports: './index.js' }),
    )
    await writeFile(join(packageDirectory, 'index.js'), 'export const value = 1')
  }

  server = await createServer({
    ...config,
    configFile: false,
    root: directory,
    logLevel: 'silent',
    server: { ...config.server, middlewareMode: true, hmr: false },
  })
  await once(server.watcher, 'ready')
})

afterEach(async () => {
  await server?.close()
  server = undefined
  await rm(directory, { recursive: true, force: true })
})

describe('Web development scanning', () => {
  it('discovers Web dependencies without treating native reports as app entries', async () => {
    const optimizer = server!.environments.client.depsOptimizer!

    await optimizer.init()
    await optimizer.scanProcessing

    const dependencies = {
      ...optimizer.metadata.discovered,
      ...optimizer.metadata.optimized,
    }

    expect(dependencies).toHaveProperty('web-fixture-dep')
    expect(dependencies).not.toHaveProperty('native-fixture-dep-0')
    expect(dependencies).not.toHaveProperty('native-fixture-dep-1')
  })

  it('watches Web edits without crawling native build output', async () => {
    const changes: string[] = []
    const sourceDirectory = join(directory, 'src')
    const sourceFile = join(sourceDirectory, 'main.js')

    server!.watcher.on('change', (file) => changes.push(file))
    await vi.waitFor(() => {
      expect(server!.watcher.getWatched()[sourceDirectory]).toContain('main.js')
    })
    await writeFile(sourceFile, 'export const value = 2')
    await vi.waitFor(() => expect(changes).toContain(sourceFile))

    const watchedDirectories = Object.keys(server!.watcher.getWatched())

    for (const nativeRoot of ['android', 'src-tauri']) {
      expect(
        watchedDirectories.some((path) => relative(directory, path).split(sep)[0] === nativeRoot),
      ).toBe(false)
    }
  })
})
