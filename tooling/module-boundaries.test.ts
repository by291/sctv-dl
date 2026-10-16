import { ESLint } from 'eslint'
import { describe, expect, it } from 'vitest'

import type { Linter } from 'eslint'

const lint = new ESLint()

type ImportFixture = [filePath: string, target: string]

async function importMessages(filePath: string, source: string): Promise<Linter.LintMessage[]> {
  const results = await lint.lintText(source, { filePath })

  return results
    .flatMap(({ messages }) => messages)
    .filter((message) =>
      ['no-restricted-imports', 'no-restricted-syntax'].includes(message.ruleId ?? ''),
    )
}

const restrictedImports: ImportFixture[] = [
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
  ['shared/contracts/fixture.ts', '../../src/main.ts'],
  ['shared/contracts/fixture.ts', '../../server/main.ts'],
  ['shared/contracts/fixture.ts', 'node:fs/promises'],
  ['shared/contracts/fixture.ts', 'fs'],
  ['shared/contracts/fixture.ts', '@tauri-apps/api/core'],
  ['shared/contracts/fixture.ts', 'vue'],
  ['shared/contracts/fixture.ts', 'vue-router'],
  ['shared/contracts/fixture.ts', 'pinia'],
  ['shared/contracts/fixture.ts', '@vueuse/core'],
  ['shared/contracts/fixture.ts', 'naive-ui'],
  ['src/features/programmes/api/fixture.ts', '@/platform/web-platform'],
  ['src/features/programmes/components/Fixture.vue', '@/platform/tauri-platform'],
  ['src/features/programmes/components/Fixture.vue', '@tauri-apps/api/core'],
]

const permittedImports: ImportFixture[] = [
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
  ['shared/contracts/fixture.ts', 'zod'],
  ['shared/contracts/fixture.ts', './programmes.ts'],
  ['shared/contracts/fixture.test.ts', 'node:fs/promises'],
  ['src/router/fixture.ts', '@/features/programmes/views/ProgrammeLibraryView.vue'],
  ['src/layouts/AppLayout.vue', '@/features/downloads/components/DownloadTasksPanel.vue'],
  ['src/platform/fixture.ts', '@/platform/tauri-platform'],
  ['src/platform/fixture.ts', '@tauri-apps/api/core'],
]

describe.each(['static', 'dynamic', 'template'] as const)(
  'module dependency boundaries: %s imports',
  (kind) => {
    function importSource(filePath: string, target: string): string {
      const statement = {
        static: `import '${target}'`,
        dynamic: `void import('${target}')`,
        template: `void import(\`${target}\`)`,
      }[kind]

      return filePath.endsWith('.vue')
        ? `<script setup lang="ts">\n${statement}\n</script>\n<template><div /></template>`
        : statement
    }

    it.each(restrictedImports)('rejects %s importing %s', async (filePath, target) => {
      expect(await importMessages(filePath, importSource(filePath, target))).not.toEqual([])
    })

    it.each(permittedImports)('allows %s importing %s', async (filePath, target) => {
      expect(await importMessages(filePath, importSource(filePath, target))).toEqual([])
    })
  },
)
