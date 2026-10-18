import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve, join } from 'node:path'
import { execFileSync, spawnSync } from 'node:child_process'
import { afterEach, expect, it } from 'vitest'

const script = resolve('tooling/desktop-release.ts')
const roots: string[] = []
const gitEnv = {
  ...process.env,
  GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null',
  GIT_CONFIG_NOSYSTEM: '1',
}

function gitAt(root: string, ...args: string[]): string {
  return execFileSync('git', args, { cwd: root, env: gitEnv, encoding: 'utf8' }).trim()
}

function createReleaseRepository(): string {
  const root = mkdtempSync(join(tmpdir(), 'sctv-release-'))
  roots.push(root)
  mkdirSync(join(root, 'src-tauri'))
  writeFileSync(join(root, 'package.json'), JSON.stringify({ version: '0.1.0' }))
  writeFileSync(join(root, 'src-tauri/tauri.conf.json'), JSON.stringify({ version: '0.1.0' }))
  writeFileSync(join(root, 'src-tauri/Cargo.toml'), '[package]\nversion = "0.1.0"\n')

  gitAt(root, 'init', '--quiet', '--initial-branch=main')
  gitAt(root, 'config', 'user.name', 'Release fixture')
  gitAt(root, 'config', 'user.email', 'release@example.invalid')
  gitAt(root, 'commit', '--quiet', '--allow-empty', '-m', 'Tagged source')
  gitAt(root, 'tag', 'v0.1.0')

  return root
}

const credentials = Object.fromEntries(
  [
    'APPLE_CERTIFICATE',
    'APPLE_CERTIFICATE_PASSWORD',
    'APPLE_SIGNING_IDENTITY',
    'APPLE_ID',
    'APPLE_PASSWORD',
    'APPLE_TEAM_ID',
  ].map((name) => [name, `fixture-${name}`]),
)

afterEach(() => {
  for (const root of roots.splice(0)) {
    rmSync(root, { recursive: true, force: true })
  }
})

it('rejects mismatched release tags and inconsistent application versions', () => {
  const root = createReleaseRepository()
  const run = (tag: string) =>
    spawnSync(process.execPath, [script, 'version'], {
      cwd: root,
      env: { ...process.env, RELEASE_TAG: tag },
    })
  expect(run('v0.1.0').status).toBe(0)
  expect(run('v0.2.0').status).toBe(1)
  writeFileSync(join(root, 'src-tauri/Cargo.toml'), '[package]\nversion = "0.2.0"\n')
  expect(run('v0.1.0').status).toBe(1)
})

it('refuses unsigned macOS release preparation without exposing credentials', () => {
  const root = createReleaseRepository()
  const result = spawnSync(process.execPath, [script, 'macos'], {
    cwd: root,
    env: { ...process.env, ...credentials, APPLE_PASSWORD: '' },
    encoding: 'utf8',
  })
  expect(result.status).toBe(1)
  expect(result.stderr).toContain('Missing release credential: APPLE_PASSWORD')
  expect(result.stderr).not.toContain('fixture-APPLE_CERTIFICATE')
  expect(existsSync(join(root, 'src-tauri/tauri.release.conf.json'))).toBe(false)
})

it('overrides ad-hoc signing only after all macOS release credentials are present', () => {
  const root = createReleaseRepository()
  const result = spawnSync(process.execPath, [script, 'macos'], {
    cwd: root,
    env: { ...process.env, ...credentials },
  })
  expect(result.status).toBe(0)
  expect(JSON.parse(readFileSync(join(root, 'src-tauri/tauri.release.conf.json'), 'utf8'))).toEqual(
    { bundle: { macOS: { signingIdentity: 'fixture-APPLE_SIGNING_IDENTITY' } } },
  )
})

it('resolves only an existing tag and rejects a shadow branch or mismatched checkout', () => {
  const root = createReleaseRepository()
  const env = { ...gitEnv, RELEASE_TAG: 'v0.1.0', GITHUB_OUTPUT: join(root, 'output') }
  const git = (...args: string[]) => gitAt(root, ...args)
  const revision = git('rev-parse', 'HEAD')
  git('commit', '--quiet', '--allow-empty', '-m', 'Different source')
  git('branch', 'v0.1.0')
  const run = () =>
    spawnSync(process.execPath, [script, 'revision'], { cwd: root, env, encoding: 'utf8' })
  expect(spawnSync(process.execPath, [script, 'version'], { cwd: root, env }).status).toBe(1)
  expect(run().status).toBe(1)
  git('checkout', '--quiet', '--detach', 'refs/tags/v0.1.0')
  expect(run().status).toBe(0)
  expect(readFileSync(join(root, 'output'), 'utf8')).toContain(`commit=${revision}\n`)
  git('tag', '-d', 'v0.1.0')
  expect(run().status).toBe(1)
})

it.each([
  ['package.json', null],
  ['package.json', { version: 1 }],
  ['src-tauri/tauri.conf.json', { version: '' }],
  ['src-tauri/tauri.conf.json', []],
] as const)(
  'identifies invalid version metadata in %s before release preparation',
  (file, metadata) => {
    const root = createReleaseRepository()
    writeFileSync(join(root, file), JSON.stringify(metadata))

    const result = spawnSync(process.execPath, [script, 'version'], {
      cwd: root,
      env: { ...gitEnv, RELEASE_TAG: 'v0.1.0' },
      encoding: 'utf8',
    })

    expect(result.status).toBe(1)
    expect(result.stderr.split('\n').find((line) => line.startsWith('Error:'))).toContain(file)
    expect(existsSync(join(root, 'src-tauri/tauri.release.conf.json'))).toBe(false)
  },
)

it('reads the Cargo package version independently of dependency table order', () => {
  const root = createReleaseRepository()
  writeFileSync(
    join(root, 'src-tauri/Cargo.toml'),
    '[dependencies.example]\nversion = "9.9.9"\n\n[package]\nversion = "0.1.0"\n',
  )

  const result = spawnSync(process.execPath, [script, 'version'], {
    cwd: root,
    env: { ...gitEnv, RELEASE_TAG: 'v0.1.0' },
  })

  expect(result.status).toBe(0)
})
