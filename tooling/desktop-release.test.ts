import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve, join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { afterEach, expect, it } from 'vitest'

const script = resolve('tooling/desktop-release.ts')
const roots: string[] = []

function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'sctv-release-'))
  roots.push(root)
  mkdirSync(join(root, 'src-tauri'))
  writeFileSync(join(root, 'package.json'), JSON.stringify({ version: '0.1.0' }))
  writeFileSync(join(root, 'src-tauri/tauri.conf.json'), JSON.stringify({ version: '0.1.0' }))
  writeFileSync(join(root, 'src-tauri/Cargo.toml'), '[package]\nversion = "0.1.0"\n')

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
  const root = fixture()
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
  const root = fixture()
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
  const root = fixture()
  const result = spawnSync(process.execPath, [script, 'macos'], {
    cwd: root,
    env: { ...process.env, ...credentials },
  })
  expect(result.status).toBe(0)
  expect(JSON.parse(readFileSync(join(root, 'src-tauri/tauri.release.conf.json'), 'utf8'))).toEqual(
    { bundle: { macOS: { signingIdentity: 'fixture-APPLE_SIGNING_IDENTITY' } } },
  )
})
