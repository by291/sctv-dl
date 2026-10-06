import js from '@eslint/js'
import ts from 'typescript-eslint'
import vue from 'eslint-plugin-vue'
import prettier from 'eslint-config-prettier'
import globals from 'globals'
import stylistic from '@stylistic/eslint-plugin'

export default ts.config(
  { ignores: ['dist/**', 'node_modules/**', '.cache/**', '.superpowers/**'] },
  js.configs.recommended,
  ...ts.configs.recommended,
  ...vue.configs['flat/recommended'],
  prettier,
  {
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
  { files: ['server/**/*.ts', '*.{js,ts}'], languageOptions: { globals: globals.node } },
  {
    files: ['**/*.vue'],
    languageOptions: { parserOptions: { parser: ts.parser } },
    rules: {
      'vue/component-api-style': ['error', ['script-setup']],
      'vue/block-order': ['error', { order: ['script', 'template', 'style'] }],
    },
  },
)
