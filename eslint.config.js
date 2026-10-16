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
import { builtinModules } from 'node:module'

const nativeApiImportPattern = {
  regex: '^@tauri-apps/',
  message: 'Vue components must consume platform ports rather than native APIs.',
}

const browserImportPatterns = [
  { regex: '^\\.', message: 'Use @/ aliases for browser modules.' },
  { regex: '(?:^|/)server(?:/|$)', message: 'Browser modules must not import server code.' },
]

const featureImportPatterns = [
  ...browserImportPatterns,
  {
    regex: '^@/(?:App(?:\\.|$)|main(?:\\.|$)|layouts/|router(?:/|$)|theme/|platform/)',
    message: 'Business and shared modules must not depend on application composition.',
  },
]

const sharedImportPatterns = [
  {
    regex: '^@/|(?:^|/)(?:src|server)(?:/|$)',
    message: 'Shared contracts must not depend on browser or server implementations.',
  },
]

const contractImportPatterns = [
  ...sharedImportPatterns,
  {
    regex: `^node:|^(?:${builtinModules.join('|')})(?:/|$)|^@tauri-apps/`,
    message: 'Shared contracts must not depend on Node or native platform APIs.',
  },
  {
    regex: '^(?:vue|vue-router|pinia|@vueuse/[^/]+|naive-ui|artplayer|@lucide/vue)(?:/|$)',
    message: 'Shared contracts must not depend on browser frameworks.',
  },
]

function importBoundaryRules(patterns) {
  return {
    'no-restricted-imports': ['error', { patterns }],
    // Lazy imports follow the same ownership rules as static imports.
    'no-restricted-syntax': [
      'error',
      ...patterns.map(({ regex, message }) => {
        const pathPattern = regex.replaceAll('/', '\\/')

        return {
          selector: [
            `ImportExpression[source.value=/${pathPattern}/]`,
            'ImportExpression[source.type="TemplateLiteral"][source.expressions.length=0]' +
              `[source.quasis.0.value.cooked=/${pathPattern}/]`,
          ].join(', '),
          message,
        }
      }),
    ],
  }
}

function browserImportBoundaries(root, patterns, ignores = []) {
  return ['ts', 'vue'].map((extension) => ({
    files: [`${root}/**/*.${extension}`],
    ignores,
    rules: importBoundaryRules(
      extension === 'vue' ? [...patterns, nativeApiImportPattern] : patterns,
    ),
  }))
}

export default defineConfig(
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      '.cache/**',
      '.superpowers/**',
      'android/**',
      'src-tauri/target/**',
      'src-tauri/gen/**',
    ],
  },
  {
    files: ['shared/**/*.ts'],
    rules: importBoundaryRules(sharedImportPatterns),
  },
  {
    files: ['shared/contracts/**/*.ts'],
    ignores: ['shared/**/*.test.ts'],
    rules: importBoundaryRules(contractImportPatterns),
  },
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
  {
    files: ['src/**/*.{ts,vue}'],
    languageOptions: { globals: globals.browser },
  },
  ...browserImportBoundaries('src', browserImportPatterns),
  ...browserImportBoundaries('src/features', featureImportPatterns, ['src/**/*.test.ts']),
  ...browserImportBoundaries(
    'src/shared',
    [
      ...featureImportPatterns,
      {
        regex: '^@/features/',
        message: 'Shared modules must be feature-independent.',
      },
    ],
    ['src/**/*.test.ts'],
  ),
  {
    files: ['src/features/programmes/{api,model}/**/*.ts'],
    ignores: ['src/**/*.test.ts'],
    rules: importBoundaryRules([
      ...featureImportPatterns,
      {
        regex: '^@/features/(?!programmes/(?:api|model)/)',
        message:
          'Programme data and domain rules may only depend on data/domain or shared modules.',
      },
    ]),
  },
  {
    files: ['server/**/*.ts'],
    rules: importBoundaryRules([
      {
        regex: '^(?:@/|vite(?:/|$)|@vitejs/)|(?:^|/)(?:src|tooling)(?:/|$)',
        message: 'The production server must not depend on browser or build tooling modules.',
      },
    ]),
  },
  {
    files: ['server/**/*.ts', '*.{js,ts}', 'tooling/**/*.{js,ts}'],
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
