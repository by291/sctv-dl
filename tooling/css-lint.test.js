import { ESLint } from 'eslint'
import { describe, expect, it } from 'vitest'

const lint = new ESLint()

describe('CSS lint configuration', () => {
  it.each([
    { filePath: 'src/styles/lint-fixture.css', source: '.panel { padding: invalid; }', line: 1 },
    {
      filePath: 'src/CssLintFixture.vue',
      source:
        '<template><div class="panel" /></template>\n<style scoped>\n.panel { padding: invalid; }\n</style>',
      line: 3,
    },
  ])('reports invalid native declarations in $filePath', async ({ filePath, source, line }) => {
    const [result] = await lint.lintText(source, { filePath })

    expect(result.messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ ruleId: 'css/no-invalid-properties', line }),
      ]),
    )
  })

  it('accepts native responsive rules in multiple Vue style blocks', async () => {
    const source = `<template><div class="panel" /></template>
<style scoped>
.panel { padding: 11px; color: var(--text); }
@media (width < 760px) { .panel { padding: 0; } }
</style>
<style>
:root { --text: #242a33; }
</style>`
    const [result] = await lint.lintText(source, { filePath: 'src/CssLintFixture.vue' })

    expect(result.errorCount).toBe(0)
  })
})
