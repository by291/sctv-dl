import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, relative, sep } from 'node:path'
import { createServer } from 'vite'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import config from '../vite.config.ts'

import type { ViteDevServer } from 'vite'

let directory: string
let server: ViteDevServer | undefined

beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), 'sctv-vite-startup-'))
  const reportDirectory = join(directory, 'android/app/build/reports')

  await mkdir(join(directory, 'src'))
  await mkdir(reportDirectory, { recursive: true })
  await writeFile(
    join(directory, 'index.html'),
    '<script type="module" src="/src/main.js"></script>',
  )
  await writeFile(join(directory, 'src/main.js'), "export { value } from 'web-fixture-dep'")
  await writeFile(
    join(reportDirectory, 'index.html'),
    '<script type="module">import "android-fixture-dep"</script>',
  )

  for (const name of ['web-fixture-dep', 'android-fixture-dep']) {
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
})

afterEach(async () => {
  await server?.close()
  server = undefined
  await rm(directory, { recursive: true, force: true })
})

describe('Web development scanning', () => {
  it('discovers Web dependencies without treating Android reports as app entries', async () => {
    const optimizer = server!.environments.client.depsOptimizer!

    await optimizer.init()
    await optimizer.scanProcessing

    const dependencies = {
      ...optimizer.metadata.discovered,
      ...optimizer.metadata.optimized,
    }

    expect(dependencies).toHaveProperty('web-fixture-dep')
    expect(dependencies).not.toHaveProperty('android-fixture-dep')
  })

  it('watches Web edits without crawling Android build output', async () => {
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

    expect(
      watchedDirectories.some((path) => relative(directory, path).split(sep)[0] === 'android'),
    ).toBe(false)
  })
})
