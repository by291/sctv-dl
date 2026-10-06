import { ESLint } from 'eslint'
import { describe, expect, it } from 'vitest'

const lint = new ESLint()
const autofix = new ESLint({ fix: true })

// The first lint starts Tailwind's compiler worker alongside the application test suite.
describe('Tailwind lint configuration', { timeout: 15_000 }, () => {
  it('checks static and bound Vue template classes', async () => {
    const source = `<script setup lang="ts">
const active = true
</script>
<template>
  <div class="w-[232px]" :class="{ 'h-[80px]': active }" />
</template>`
    const [result] = await lint.lintText(source, { filePath: 'src/TailwindLintFixture.vue' })

    expect(
      result.messages.filter((message) => message.ruleId?.endsWith('enforce-canonical-classes')),
    ).toHaveLength(2)

    const [fixed] = await autofix.lintText(source, { filePath: 'src/TailwindLintFixture.vue' })

    expect(fixed.errorCount).toBe(0)
    expect(fixed.output).toContain('class="w-58"')
    expect(fixed.output).toContain("'h-20': active")
  })

  it('fixes multiple scoped style blocks without changing the surrounding Vue source', async () => {
    const template = '<template><div class="sidebar" /></template>'
    const source = `${template}\r\n<style scoped>\r\n.sidebar { @apply w-[232px]; }\r\n</style>\r\n<style>\r\n.panel { @apply h-[80px]; }\r\n</style>`
    const [result] = await lint.lintText(source, { filePath: 'src/TailwindLintFixture.vue' })

    expect(result.messages.map((message) => message.line)).toEqual([3, 6])

    const [fixed] = await autofix.lintText(source, { filePath: 'src/TailwindLintFixture.vue' })

    expect(fixed.errorCount).toBe(0)
    expect(fixed.output).toBe(source.replace('w-[232px]', 'w-58').replace('h-[80px]', 'h-20'))
  })

  it('checks CSS @apply including variants and preserves intentional transform properties', async () => {
    const source = '.panel { @apply w-[232px] hover:transform-[translateY(-3px)]; }'
    const [fixed] = await autofix.lintText(source, { filePath: 'src/styles/lint-fixture.css' })

    expect(fixed.errorCount).toBe(0)
    expect(fixed.output).toBe(source.replace('w-[232px]', 'w-58'))
  })

  it('reports conflicting utilities and fixes duplicate classes', async () => {
    const [conflict] = await lint.lintText('<template><div class="w-58 w-60" /></template>', {
      filePath: 'src/TailwindLintFixture.vue',
    })

    expect(
      conflict.messages.some((message) => message.ruleId?.endsWith('no-conflicting-classes')),
    ).toBe(true)

    const [fixed] = await autofix.lintText('<template><div class="w-58 w-58" /></template>', {
      filePath: 'src/TailwindLintFixture.vue',
    })

    expect(fixed.errorCount).toBe(0)
    expect(fixed.output).toContain('class="w-58"')
  })
})
