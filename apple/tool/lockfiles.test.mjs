import assert from 'node:assert/strict'
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises'
import { join, dirname } from 'node:path'
import { tmpdir } from 'node:os'
import test from 'node:test'
import { prepareApplicationLock, readLockfiles, verifyLockfiles } from './lockfiles.mjs'

const packagePath = 'apple/Packages/SCTVKit/Package.resolved'
const applicationPath =
  'apple/SCTV.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
const pin = {
  identity: 'grdb.swift',
  kind: 'remoteSourceControl',
  location: 'https://github.com/groue/GRDB.swift.git',
  state: { version: '7.11.1', revision: 'a'.repeat(40) },
}

async function withLocks(action) {
  const root = await mkdtemp(join(tmpdir(), 'sctv-lockfiles-'))
  try {
    await mkdir(dirname(join(root, packagePath)), { recursive: true })
    await writeFile(
      join(root, packagePath),
      JSON.stringify({ version: 3, originHash: 'package-hash', pins: [pin] }),
    )
    await action(root)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
}

test('generates the Xcode lock from a package-only dependency update', async () => {
  await withLocks(async (root) => {
    const original = await readFile(join(root, packagePath), 'utf8')
    await prepareApplicationLock(root)
    const generated = JSON.parse(await readFile(join(root, applicationPath), 'utf8'))
    assert.deepEqual(generated.pins, [pin])
    assert.equal(generated.originHash, undefined)
    assert.equal(await readFile(join(root, packagePath), 'utf8'), original)

    const updated = original.replace('7.11.1', '7.11.2').replace('a'.repeat(40), 'b'.repeat(40))
    await writeFile(join(root, packagePath), updated)
    await prepareApplicationLock(root)
    assert.equal(
      JSON.parse(await readFile(join(root, applicationPath), 'utf8')).pins[0].state.version,
      '7.11.2',
    )
    assert.equal(await readFile(join(root, packagePath), 'utf8'), updated)
    await readLockfiles(root)
  })
})

test('allows Xcode metadata rewrites but rejects changed pins or package lock bytes', async () => {
  await withLocks(async (root) => {
    await prepareApplicationLock(root)
    const before = await readLockfiles(root)
    await writeFile(
      join(root, applicationPath),
      JSON.stringify({ version: 3, originHash: 'xcode-hash', pins: [pin] }),
    )
    verifyLockfiles(before, await readLockfiles(root))

    for (const changed of [
      { ...pin, location: 'https://example.com/other.git' },
      { ...pin, state: { ...pin.state, revision: 'b'.repeat(40) } },
    ]) {
      await writeFile(join(root, applicationPath), JSON.stringify({ version: 2, pins: [changed] }))
      await assert.rejects(readLockfiles(root), /pins differ/)
    }

    await prepareApplicationLock(root)
    await writeFile(
      join(root, packagePath),
      (await readFile(join(root, packagePath), 'utf8')) + '\n',
    )
    const after = await readLockfiles(root)
    assert.throws(() => verifyLockfiles(before, after), /changed/)
  })
})

test('rejects malformed or unpinned dependencies before replacing the application lock', async () => {
  await withLocks(async (root) => {
    await prepareApplicationLock(root)
    const original = await readFile(join(root, applicationPath), 'utf8')
    for (const lock of [
      null,
      { version: 1, pins: [pin] },
      { version: 3, pins: [] },
      { version: 3, pins: [pin, pin] },
      { version: 3, pins: [{ ...pin, state: { revision: 'a'.repeat(40) } }] },
    ]) {
      await writeFile(join(root, packagePath), JSON.stringify(lock))
      await assert.rejects(prepareApplicationLock(root), /Invalid stable dependency lockfile/)
      assert.equal(await readFile(join(root, applicationPath), 'utf8'), original)
    }
  })
})
