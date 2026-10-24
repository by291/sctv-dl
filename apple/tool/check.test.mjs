import assert from 'node:assert/strict'
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import {
  selectSimulator,
  runProcess,
  withSimulator,
  readLockfiles,
  verifyLockfiles,
  parseOptions,
} from './check.mjs'

test('missing requested OS is rejected instead of selecting a newer runtime', () => {
  assert.throws(
    () =>
      selectSimulator(
        {
          runtimes: [
            {
              isAvailable: true,
              version: '27.0',
              platform: 'iOS',
              identifier: 'ios27',
              supportedDeviceTypes: [{ identifier: 'phone', productFamily: 'iPhone' }],
            },
          ],
        },
        'iphone',
        '26',
      ),
    /Unavailable/,
  )
})

test('matching runtime selects the requested device family', () => {
  const selected = selectSimulator(
    {
      runtimes: [
        {
          isAvailable: true,
          version: '26.2',
          platform: 'iOS',
          identifier: 'ios26',
          supportedDeviceTypes: [
            { identifier: 'tablet', productFamily: 'iPad' },
            { identifier: 'phone', productFamily: 'iPhone' },
          ],
        },
      ],
    },
    'ipad',
    '26',
  )
  assert.deepEqual(selected, { runtime: 'ios26', deviceType: 'tablet', version: '26.2' })
})

test('subprocess failures retain a nonzero exit result', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'sctv-apple-check-'))
  try {
    await assert.rejects(
      runProcess(process.execPath, ['-e', 'process.exit(7)'], {
        logPath: join(directory, 'run.log'),
      }),
      /exit 7/,
    )
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})

test('only the newly created simulator is removed after failure', async () => {
  const calls = []
  const execute = async (command, args) => {
    calls.push([command, ...args])

    return args[1] === 'create' ? 'owned-device\n' : ''
  }

  await assert.rejects(
    withSimulator({ runtime: 'ios26', deviceType: 'phone' }, execute, async () => {
      throw new Error('test failure')
    }),
    /test failure/,
  )
  assert.deepEqual(calls.slice(-2), [
    ['xcrun', 'simctl', 'shutdown', 'owned-device'],
    ['xcrun', 'simctl', 'delete', 'owned-device'],
  ])
})

test('Release selects unsigned compilation and rejects invalid configurations', () => {
  assert.equal(
    parseOptions(['--platform', 'ios', '--configuration', 'Release']).configuration,
    'Release',
  )
  assert.throws(
    () => parseOptions(['--platform', 'ios', '--configuration', 'Unknown']),
    /configuration/,
  )
})

test('locked validation rejects changed or missing dependency resolution', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'sctv-apple-locks-'))
  const locations = [
    'apple/Packages/SCTVKit/Package.resolved',
    'apple/SCTV.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
  ]
  const lock = JSON.stringify({
    version: 3,
    pins: [
      {
        identity: 'grdb.swift',
        kind: 'remoteSourceControl',
        location: 'https://github.com/groue/GRDB.swift.git',
        state: { version: '7.11.1', revision: 'a'.repeat(40) },
      },
    ],
  })
  try {
    await assert.rejects(readLockfiles(directory), /ENOENT/)
    for (const file of locations) {
      await mkdir(join(directory, file, '..'), { recursive: true })
      await writeFile(join(directory, file), lock)
    }

    const before = await readLockfiles(directory)
    verifyLockfiles(before, await readLockfiles(directory))
    await writeFile(join(directory, locations[0]), lock.replace('7.11.1', '7.11.2'))
    assert.throws(
      () => verifyLockfiles(before, { ...before, [locations[0]]: 'changed' }),
      /changed/,
    )
    await assert.rejects(readLockfiles(directory), /differ/)
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})

test('all-platform CI validation permits only unsigned Release builds without device options', () => {
  assert.equal(parseOptions(['--platform', 'all', '--configuration', 'Release']).platform, 'all')
  assert.throws(() => parseOptions(['--platform', 'all']), /Release/)
  assert.throws(
    () => parseOptions(['--platform', 'all', '--configuration', 'Release', '--device', 'iphone']),
    /device/,
  )
})
