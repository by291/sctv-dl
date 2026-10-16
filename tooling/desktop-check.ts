import { spawnSync } from 'node:child_process'

for (const args of [
  ['fmt', '--manifest-path', 'src-tauri/Cargo.toml', '--', '--check'],
  [
    'clippy',
    '--manifest-path',
    'src-tauri/Cargo.toml',
    '--all-targets',
    '--locked',
    '--',
    '-D',
    'warnings',
  ],
  ['test', '--manifest-path', 'src-tauri/Cargo.toml', '--locked'],
]) {
  const result = spawnSync('cargo', args, { stdio: 'inherit' })
  if (result.error) {
    console.error(result.error.message)
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1)
  }
}
