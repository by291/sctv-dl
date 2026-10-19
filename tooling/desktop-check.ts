import { spawnSync } from 'node:child_process'
import { availableParallelism } from 'node:os'

const manifestPath = 'src-tauri/Cargo.toml'

// Limit only this check's Cargo children; preserve explicit Cargo overrides.
const cargoEnv = {
  ...process.env,
  CARGO_BUILD_JOBS: process.env.CARGO_BUILD_JOBS ?? String(Math.min(4, availableParallelism())),
}

for (const args of [
  ['fmt', '--manifest-path', manifestPath, '--', '--check'],
  [
    'clippy',
    '--manifest-path',
    manifestPath,
    '--all-targets',
    '--locked',
    '--',
    '-D',
    'warnings',
  ],
  ['test', '--manifest-path', manifestPath, '--locked'],
]) {
  const result = spawnSync('cargo', args, { stdio: 'inherit', env: cargoEnv })

  if (result.error) {
    console.error(`cargo ${args[0]} could not start: ${result.error.message}`)
    process.exit(1)
  }

  if (result.status !== 0) {
    console.error(`cargo ${args[0]} failed with exit code ${result.status ?? 'unknown'}.`)
    process.exit(result.status ?? 1)
  }
}
