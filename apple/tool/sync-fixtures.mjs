import { copyFile, mkdir, readdir } from 'node:fs/promises'

const source = new URL('../../shared/fixtures/', import.meta.url)
const destination = new URL('../Packages/SCTVKit/Tests/SCTVCoreTests/Fixtures/', import.meta.url)
const dataDestination = new URL(
  '../Packages/SCTVKit/Tests/SCTVDataTests/Fixtures/',
  import.meta.url,
)

await mkdir(destination, { recursive: true })
await mkdir(dataDestination, { recursive: true })
for (const file of await readdir(source)) {
  if (file.endsWith('.json')) {
    await copyFile(new URL(file, source), new URL(file, destination))
    await copyFile(new URL(file, source), new URL(file, dataDestination))
  }
}

const video = new URL('../build/fixtures/probe.mp4', import.meta.url)
for (const folder of [
  '../Packages/SCTVKit/Tests/SCTVMediaTests/Fixtures/',
  '../Packages/SCTVKit/Tests/SCTVDownloadsTests/Fixtures/',
  '../Apps/Shared/Fixtures/',
]) {
  const target = new URL(folder, import.meta.url)
  await mkdir(target, { recursive: true })
  await copyFile(video, new URL('probe.mp4', target))
}
