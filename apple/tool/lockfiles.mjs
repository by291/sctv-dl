import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const repository = fileURLToPath(new URL('../../', import.meta.url))
const packagePath = 'apple/Packages/SCTVKit/Package.resolved'
const applicationPath =
  'apple/SCTV.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'

function parseLockfile(text, path) {
  const lock = JSON.parse(text)
  if (
    ![2, 3].includes(lock?.version) ||
    !Array.isArray(lock.pins) ||
    lock.pins.length === 0 ||
    lock.pins.some(
      (pin) =>
        typeof pin?.identity !== 'string' ||
        !pin.identity ||
        pin.kind !== 'remoteSourceControl' ||
        typeof pin.location !== 'string' ||
        !pin.location ||
        !/^\d+\.\d+\.\d+$/.test(pin.state?.version) ||
        !/^[a-f0-9]{40}$/.test(pin.state?.revision),
    ) ||
    new Set(lock.pins.map((pin) => pin.identity)).size !== lock.pins.length
  ) {
    throw new Error(`Invalid stable dependency lockfile: ${path}`)
  }
  return lock
}

function resolutions(lock) {
  return JSON.stringify(
    lock.pins
      .map((pin) => [pin.identity, pin.kind, pin.location, pin.state.version, pin.state.revision])
      .sort(),
  )
}

export async function prepareApplicationLock(root = repository) {
  const text = await readFile(resolve(root, packagePath), 'utf8')
  const lock = parseLockfile(text, packagePath)
  // Version 2 carries the same pins without copying the package manifest's originHash
  // into a different Xcode dependency graph. Xcode may add its own metadata later.
  const application = JSON.stringify({ version: 2, pins: lock.pins }, null, 2) + '\n'
  await mkdir(dirname(resolve(root, applicationPath)), { recursive: true })
  await writeFile(resolve(root, applicationPath), application)
}

export async function readLockfiles(root) {
  const files = {}
  const pins = []
  for (const path of [packagePath, applicationPath]) {
    const text = await readFile(resolve(root, path), 'utf8')
    files[path] = text
    pins.push(resolutions(parseLockfile(text, path)))
  }
  if (pins[0] !== pins[1]) {
    throw new Error('Package and application dependency pins differ')
  }
  return files
}

export function verifyLockfiles(before, after) {
  if (before[packagePath] !== after[packagePath]) {
    throw new Error(`Dependency lockfile changed: ${packagePath}`)
  }
  const expected = resolutions(parseLockfile(before[packagePath], packagePath))
  for (const path of [packagePath, applicationPath]) {
    if (expected !== resolutions(parseLockfile(after[path], path))) {
      throw new Error(`Dependency lockfile changed: ${path}`)
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  prepareApplicationLock()
    .then(() => console.log('Prepared Xcode dependency pins from SCTVKit.'))
    .catch((error) => {
      console.error(error.message)
      process.exitCode = 1
    })
}
