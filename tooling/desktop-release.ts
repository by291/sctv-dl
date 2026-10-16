import { appendFileSync, readFileSync, writeFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

function releaseRevision(): string {
  const tag = process.env.RELEASE_TAG
  if (!tag || !/^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(tag)) {
    throw new Error('An explicit version tag is required.')
  }

  const git = (...args: string[]) => execFileSync('git', args, { encoding: 'utf8' }).trim()
  const revision = git('rev-parse', '--verify', `refs/tags/${tag}^{commit}`)
  if (revision !== git('rev-parse', 'HEAD')) {
    throw new Error('The release tag must point to the checked-out source commit.')
  }

  return revision
}

const mode = process.argv[2]
if (mode === 'version') {
  const packageVersion = JSON.parse(readFileSync('package.json', 'utf8')).version as string
  const configVersion = JSON.parse(readFileSync('src-tauri/tauri.conf.json', 'utf8'))
    .version as string
  const cargoVersion = readFileSync('src-tauri/Cargo.toml', 'utf8').match(
    /^version = "([^"]+)"$/m,
  )?.[1]
  if (
    process.env.RELEASE_TAG !== `v${packageVersion}` ||
    configVersion !== packageVersion ||
    cargoVersion !== packageVersion
  ) {
    throw new Error('The existing release tag must match the package, Tauri, and Cargo versions.')
  }

  releaseRevision()
} else if (mode === 'revision') {
  const revision = releaseRevision()
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `commit=${revision}\n`)
  }

  console.log(revision)
} else if (mode === 'macos') {
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

  writeFileSync(
    'src-tauri/tauri.release.conf.json',
    JSON.stringify({ bundle: { macOS: { signingIdentity: process.env.APPLE_SIGNING_IDENTITY } } }),
  )
} else {
  throw new Error('Expected version, revision, or macos release preparation mode.')
}
