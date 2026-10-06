import js from '@eslint/js'
import ts from 'typescript-eslint'
import vue from 'eslint-plugin-vue'
import prettier from 'eslint-config-prettier'
import globals from 'globals'
import stylistic from '@stylistic/eslint-plugin'
import { defineConfig } from 'eslint/config'
import css from '@eslint/css'
import tailwind from 'eslint-plugin-better-tailwindcss'
import { tailwind4 } from 'tailwind-csstree'
import { mergeProcessors } from 'eslint-merge-processors'
import vueBlocks from 'eslint-processor-vue-blocks'

const tailwindRules = {
  'better-tailwindcss/enforce-canonical-classes': ['error', { collapse: false, logical: false }],
  'better-tailwindcss/enforce-consistent-class-order': ['error', { order: 'official' }],
  'better-tailwindcss/no-duplicate-classes': 'error',
  'better-tailwindcss/no-unnecessary-whitespace': 'error',
  'better-tailwindcss/no-conflicting-classes': 'error',
  'better-tailwindcss/no-deprecated-classes': 'error',
}

export default defineConfig(
  { ignores: ['dist/**', 'node_modules/**', '.cache/**', '.superpowers/**'] },
  {
    files: ['**/*.{js,mjs,cjs,ts,mts,cts,vue}'],
    extends: [
      js.configs.recommended,
      ...ts.configs.recommended,
      ...vue.configs['flat/recommended'],
      prettier,
    ],
    plugins: { '@stylistic': stylistic },
    rules: {
      curly: ['error', 'all'],
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { fixStyle: 'separate-type-imports' },
      ],
      '@stylistic/padding-line-between-statements': [
        'error',
        { blankLine: 'always', prev: 'import', next: '*' },
        { blankLine: 'any', prev: 'import', next: 'import' },
        { blankLine: 'always', prev: '*', next: ['function', 'class', 'export'] },
        { blankLine: 'always', prev: ['function', 'class', 'block-like'], next: '*' },
        { blankLine: 'always', prev: '*', next: 'return' },
      ],
    },
  },
  { files: ['src/**/*.{ts,vue}'], languageOptions: { globals: globals.browser } },
  {
    files: ['server/**/*.ts', '*.{js,ts}', 'tooling/**/*.js'],
    languageOptions: { globals: globals.node },
  },
  {
    files: ['src/**/*.{ts,vue,css}'],
    plugins: { 'better-tailwindcss': tailwind },
    settings: {
      'better-tailwindcss': { entryPoint: 'src/styles/global.css', rootFontSize: 16 },
    },
    rules: tailwindRules,
  },
  {
    files: ['**/*.css'],
    plugins: { css },
    language: 'css/css',
    languageOptions: { customSyntax: tailwind4, tolerant: true },
  },
  {
    files: ['**/*.vue'],
    // Preserve Vue's comment directives while also linting scoped @apply rules.
    processor: mergeProcessors([
      vue.processors['.vue'],
      vueBlocks({ blocks: { styles: true, script: false, template: false, customBlocks: false } }),
    ]),
    languageOptions: { parserOptions: { parser: ts.parser } },
    rules: {
      'vue/component-api-style': ['error', ['script-setup']],
      'vue/block-order': ['error', { order: ['script', 'template', 'style'] }],
    },
  },
)
