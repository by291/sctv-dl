import { readFileSync, writeFileSync } from 'node:fs'

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
  throw new Error('Expected version or macos release preparation mode.')
}
