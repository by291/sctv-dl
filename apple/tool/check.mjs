import { spawn, execFile } from 'node:child_process'
import { mkdir, open, stat } from 'node:fs/promises'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { promisify, parseArgs } from 'node:util'

import { prepareApplicationLock, readLockfiles, verifyLockfiles } from './lockfiles.mjs'

export { readLockfiles, verifyLockfiles } from './lockfiles.mjs'

const repository = fileURLToPath(new URL('../../', import.meta.url))
const executeFile = promisify(execFile)

export function selectSimulator(inventory, family, major) {
  if (!Array.isArray(inventory?.runtimes)) {
    throw new Error('Invalid simulator runtime inventory')
  }

  const productFamily = { iphone: 'iPhone', ipad: 'iPad' }[family]
  if (!productFamily || !/^\d+$/.test(major)) {
    throw new Error('Invalid device family or OS major')
  }

  const runtimes = inventory.runtimes
    .filter(
      (runtime) =>
        runtime.isAvailable &&
        runtime.platform === 'iOS' &&
        typeof runtime.version === 'string' &&
        runtime.version.split('.')[0] === major,
    )
    .sort((left, right) => right.version.localeCompare(left.version, 'en', { numeric: true }))
  for (const runtime of runtimes) {
    const device = runtime.supportedDeviceTypes?.find(
      (type) => type.productFamily === productFamily && typeof type.identifier === 'string',
    )
    if (device && typeof runtime.identifier === 'string') {
      return {
        runtime: runtime.identifier,
        deviceType: device.identifier,
        version: runtime.version,
      }
    }
  }

  throw new Error(`Unavailable: iOS ${major} runtime for ${family}; no newer-runtime substitution`)
}

export async function runProcess(command, args, { logPath, cwd = repository }) {
  await mkdir(dirname(logPath), { recursive: true })
  const log = await open(logPath, 'w')
  try {
    await new Promise((resolveResult, reject) => {
      const child = spawn(command, args, { cwd, stdio: ['ignore', log.fd, log.fd] })
      child.once('error', reject)
      child.once('exit', (code, signal) => {
        if (code === 0) {
          resolveResult()
        } else {
          reject(
            new Error(
              `${command} failed: exit ${code}, signal ${signal ?? 'none'}; see ${logPath}`,
            ),
          )
        }
      })
    })
  } finally {
    await log.close()
  }
}

export async function withSimulator(selection, execute, action) {
  const id = (
    await execute('xcrun', [
      'simctl',
      'create',
      `SCTV validation ${Date.now()}`,
      selection.deviceType,
      selection.runtime,
    ])
  ).trim()
  if (!id) {
    throw new Error('Simulator creation returned no identity')
  }

  let failure
  let result
  try {
    await execute('xcrun', ['simctl', 'boot', id])
    await execute('xcrun', ['simctl', 'bootstatus', id, '-b'])
    result = await action(id)
  } catch (error) {
    failure = error
  } finally {
    // A test failure must survive cleanup failures; deletion is still attempted after shutdown fails.
    await execute('xcrun', ['simctl', 'shutdown', id]).catch(() => {})
    try {
      await execute('xcrun', ['simctl', 'delete', id])
    } catch (error) {
      if (!failure) {
        failure = error
      } else {
        console.error(`Could not delete owned simulator ${id}: ${error.message}`)
      }
    }
  }

  if (failure) {
    throw failure
  }

  return result
}

export function parseOptions(args = process.argv.slice(2)) {
  const { values } = parseArgs({
    args,
    options: {
      platform: { type: 'string' },
      configuration: { type: 'string', default: 'Debug' },
      'verify-lockfiles': { type: 'boolean', default: false },
      device: { type: 'string' },
      os: { type: 'string', default: '26' },
    },
  })
  if (!['ios', 'macos'].includes(values.platform)) {
    throw new Error('Use --platform ios|macos')
  }

  if (!['Debug', 'Release'].includes(values.configuration)) {
    throw new Error('Use --configuration Debug|Release')
  }

  return values
}

async function main() {
  const values = parseOptions()
  await prepareApplicationLock(repository)
  const locked = values['verify-lockfiles'] ? await readLockfiles(repository) : null
  const release = values.configuration === 'Release'
  const execute = async (command, args) =>
    (await executeFile(command, args, { cwd: repository, maxBuffer: 8 * 1024 * 1024 })).stdout
  const selection =
    values.platform === 'ios' && !release
      ? selectSimulator(
          JSON.parse(await execute('xcrun', ['simctl', 'list', 'runtimes', '-j'])),
          values.device,
          values.os,
        )
      : null
  const label = selection
    ? `${values.device}-${selection.version}`
    : `${values.platform}-${values.configuration.toLowerCase()}`
  const output = resolve(repository, 'apple/build/checks', `${label}-${Date.now()}`)
  await mkdir(output, { recursive: true })
  console.log(`Validation target: ${label}; output: ${output}`)

  const fixture = await stat(resolve(repository, 'apple/build/fixtures/probe.mp4')).catch(
    () => null,
  )
  const generator = await stat(resolve(repository, 'apple/tool/make-fixture.swift'))
  if (!fixture || fixture.mtimeMs < generator.mtimeMs) {
    await runProcess('swift', ['apple/tool/make-fixture.swift'], {
      logPath: `${output}/generate-fixture.log`,
    })
  }

  await runProcess(process.execPath, ['apple/tool/sync-fixtures.mjs'], {
    logPath: `${output}/fixtures.log`,
  })
  await runProcess(
    'swift',
    [
      'format',
      'lint',
      '--strict',
      '--recursive',
      'apple/Packages/SCTVKit/Sources',
      'apple/Packages/SCTVKit/Tests',
      'apple/Apps',
      'apple/UITests',
    ],
    { logPath: `${output}/format.log` },
  )
  await runProcess(
    'swift',
    [
      'test',
      '--package-path',
      'apple/Packages/SCTVKit',
      '--scratch-path',
      'apple/build/swift',
      ...(locked ? ['--force-resolved-versions'] : []),
    ],
    { logPath: `${output}/package.log` },
  )

  const test = async (destination) =>
    runProcess(
      'xcodebuild',
      [
        '-quiet',
        '-project',
        'apple/SCTV.xcodeproj',
        '-scheme',
        'SCTV',
        '-destination',
        destination,
        '-configuration',
        values.configuration,
        ...(locked
          ? ['-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution']
          : []),
        '-derivedDataPath',
        `apple/build/DerivedData-${values.platform}`,
        '-resultBundlePath',
        `${output}/Tests.xcresult`,
        release ? 'build' : 'test',
        ...(release ? ['CODE_SIGNING_ALLOWED=NO', 'ONLY_ACTIVE_ARCH=YES'] : []),
        'CODE_SIGN_IDENTITY=-',
        'CODE_SIGNING_REQUIRED=NO',
      ],
      { logPath: `${output}/xcode.log` },
    )

  if (selection) {
    await withSimulator(selection, execute, (id) => test(`platform=iOS Simulator,id=${id}`))
  } else {
    await test(
      values.platform === 'ios'
        ? 'generic/platform=iOS'
        : `platform=macOS,arch=${process.arch === 'arm64' ? 'arm64' : 'x86_64'}`,
    )
  }

  if (locked) {
    verifyLockfiles(locked, await readLockfiles(repository))
  }

  console.log(`Passed: ${label}`)
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error.message)
    process.exitCode = 1
  })
}
