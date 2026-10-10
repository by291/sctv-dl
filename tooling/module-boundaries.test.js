import { ESLint } from 'eslint'
import { describe, expect, it } from 'vitest'

const lint = new ESLint()

async function importMessages(filePath, source) {
  const [result] = await lint.lintText(source, { filePath })

  return result.messages.filter((message) => message.ruleId === 'no-restricted-imports')
}

describe('module dependency boundaries', () => {
  it.each([
    ['src/shared/utils/fixture.ts', '@/features/settings/stores/useSettingsStore'],
    ['src/shared/components/Fixture.vue', '@/router'],
    ['src/features/settings/fixture.ts', '@/theme/useAppTheme'],
    ['src/features/settings/fixture.ts', '@/layouts/AppLayout.vue'],
    ['src/features/programmes/model/fixture.ts', '@/features/settings/model/settings-schema'],
    [
      'src/features/programmes/model/fixture.ts',
      '@/features/programmes/composables/useProgrammeDownloads',
    ],
    [
      'src/features/programmes/api/fixture.ts',
      '@/features/programmes/stores/useProgrammeCatalogueStore',
    ],
    ['src/features/settings/fixture.ts', '../../server/main.ts'],
    ['src/features/settings/fixture.ts', '../programmes/model/programme'],
    ['src/features/programmes/composables/fixture.test.ts', '../../server/main.ts'],
    ['server/fixture.ts', '../src/shared/media/video-quality.ts'],
    ['server/fixture.ts', '../tooling/upstream-proxy-plugin.ts'],
    ['server/fixture.ts', 'vite'],
  ])('rejects %s importing %s', async (filePath, target) => {
    const source = filePath.endsWith('.vue')
      ? `<script setup lang="ts">\nimport '${target}'\n</script>\n<template><div /></template>`
      : `import '${target}'`

    expect((await importMessages(filePath, source)).length).toBeGreaterThan(0)
  })

  it.each([
    ['src/theme/fixture.ts', '@/features/settings/stores/useSettingsStore'],
    ['src/features/settings/fixture.ts', '@/shared/media/video-quality'],
    ['src/features/programmes/model/fixture.ts', '@/features/programmes/api/upstream-schemas'],
    ['src/shared/utils/fixture.ts', '@/shared/media/video-quality'],
    [
      'src/features/programmes/composables/useProgrammeCoverNavigation.test.ts',
      '@/layouts/AppLayout.vue',
    ],
    ['src/features/programmes/api/fixture.test.ts', '@/theme/useAppTheme'],
    ['src/shared/media/fixture.test.ts', '@/features/programmes/model/download-file'],
    ['server/fixture.ts', './proxy/proxy-policy.ts'],
    ['tooling/fixture.ts', '../server/proxy/proxy-middleware.ts'],
  ])('allows %s importing %s', async (filePath, target) => {
    expect(await importMessages(filePath, `import '${target}'`)).toEqual([])
  })
})
