import js from '@eslint/js'
import ts from 'typescript-eslint'
import vue from 'eslint-plugin-vue'
import prettier from 'eslint-config-prettier'
import globals from 'globals'
import stylistic from '@stylistic/eslint-plugin'
import { defineConfig } from 'eslint/config'
import css from '@eslint/css'
import { mergeProcessors } from 'eslint-merge-processors'
import vueBlocks from 'eslint-processor-vue-blocks'

export default defineConfig(
  { ignores: ['dist/**', 'node_modules/**', '.cache/**', '.superpowers/**', 'android/**'] },
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
    files: ['**/*.css'],
    plugins: { css },
    language: 'css/css',
    rules: {
      // Theme and library variables are defined outside individual style blocks.
      'css/no-invalid-properties': ['error', { allowUnknownVariables: true }],
      'css/no-invalid-at-rules': 'error',
      'css/no-invalid-at-rule-placement': 'error',
      'css/no-duplicate-imports': 'error',
      'css/no-duplicate-keyframe-selectors': 'error',
      'css/no-empty-blocks': 'error',
    },
  },
  {
    files: ['**/*.vue'],
    // Preserve Vue's comment directives while also validating component CSS.
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
