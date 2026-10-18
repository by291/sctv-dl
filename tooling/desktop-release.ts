import { appendFileSync, readFileSync, writeFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

// Source checks run before dependency installation, so this entrypoint uses only Node APIs.
function releaseTag(): string {
  const tag = process.env.RELEASE_TAG
  if (!tag || !/^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(tag)) {
    throw new Error('An explicit version tag is required.')
  }

  return tag
}

function releaseRevision(tag: string): string {
  const git = (...args: string[]) => execFileSync('git', args, { encoding: 'utf8' }).trim()
  const revision = git('rev-parse', '--verify', `refs/tags/${tag}^{commit}`)
  if (revision !== git('rev-parse', 'HEAD')) {
    throw new Error('The release tag must point to the checked-out source commit.')
  }

  return revision
}

function readJsonVersion(filename: string): string {
  let metadata: unknown
  try {
    metadata = JSON.parse(readFileSync(filename, 'utf8'))
  } catch (cause) {
    throw new Error(`Unable to read release metadata from ${filename}.`, { cause })
  }

  if (
    typeof metadata !== 'object' ||
    metadata === null ||
    Array.isArray(metadata) ||
    !('version' in metadata) ||
    typeof metadata.version !== 'string' ||
    !metadata.version.trim()
  ) {
    throw new Error(`Expected a nonempty version string in ${filename}.`)
  }

  return metadata.version
}

function readCargoVersion(): string {
  const filename = 'src-tauri/Cargo.toml'
  const lines = readFileSync(filename, 'utf8').split(/\r?\n/)
  const packageStart = lines.findIndex((line) => /^\[package\]\s*(?:#.*)?$/.test(line))
  const packageLines = lines.slice(packageStart + 1)
  const nextTable = packageLines.findIndex((line) => /^\s*\[/.test(line))
  const packageBody = packageLines.slice(0, nextTable < 0 ? undefined : nextTable).join('\n')
  // This application owns an explicit package version, not a workspace-inherited version.
  const version = packageBody.match(/^version\s*=\s*"([^"]+)"\s*(?:#.*)?$/m)?.[1]
  if (packageStart < 0 || !version) {
    throw new Error(`Expected an explicit [package] version in ${filename}.`)
  }

  return version
}

function validateReleaseVersion(): void {
  const tag = releaseTag()
  const packageVersion = readJsonVersion('package.json')
  const configVersion = readJsonVersion('src-tauri/tauri.conf.json')
  const cargoVersion = readCargoVersion()

  if (
    tag !== `v${packageVersion}` ||
    configVersion !== packageVersion ||
    cargoVersion !== packageVersion
  ) {
    throw new Error('The existing release tag must match the package, Tauri, and Cargo versions.')
  }

  releaseRevision(tag)
}

function publishSourceRevision(): void {
  const revision = releaseRevision(releaseTag())

  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `commit=${revision}\n`)
  }

  console.log(revision)
}

function prepareMacosSigning(): void {
  for (const name of [
    'APPLE_CERTIFICATE',
    'APPLE_CERTIFICATE_PASSWORD',
    'APPLE_SIGNING_IDENTITY',
    'APPLE_ID',
    'APPLE_PASSWORD',
    'APPLE_TEAM_ID',
  ]) {
    if (!process.env[name]) {
      throw new Error(`Missing release credential: ${name}`)
    }
  }

  // Validate every credential before writing; the workflow owns removal after the build.
  const config = { bundle: { macOS: { signingIdentity: process.env.APPLE_SIGNING_IDENTITY } } }
  writeFileSync('src-tauri/tauri.release.conf.json', JSON.stringify(config))
}

switch (process.argv[2]) {
  case 'version':
    validateReleaseVersion()
    break
  case 'revision':
    publishSourceRevision()
    break
  case 'macos':
    prepareMacosSigning()
    break
  default:
    throw new Error('Expected version, revision, or macos release preparation mode.')
}
