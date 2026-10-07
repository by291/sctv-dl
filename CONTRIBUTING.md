# Coding Conventions

Run `pnpm check` and `pnpm build` from the project root. Use `pnpm lint:fix` and `pnpm format` before committing to fix automatically repairable issues.

## Language

Write repository documentation, code comments, test descriptions, and commit messages in English. Localized user-facing copy and upstream programme data retain their appropriate language.

## Vue

- Use `<script setup lang="ts">` followed by the template. Component filenames use PascalCase; page components end in View.
- Define component contracts with typed `defineProps`, `defineEmits`, and `defineModel`. Use stable IDs for list keys.
- Views compose the interface and coordinate navigation and message feedback. Put request lifecycles and reusable state in `useXxx` composables.
- Use Pinia for state shared across pages. Keep preview dialogs and content selections in the owning page or composable.
- Simple expressions belong in templates. Use named functions or computed values for requests, batch operations, multistep mutations, and complex conditions.
- Check Naive UI and VueUse before writing general-purpose infrastructure. Avoid splitting every static heading into a separate component.
- Keep short Tailwind utility combinations in templates. Compose long, responsive, or repeated component styles in a co-located `<style scoped>` block using `@apply` and `@variant`. Start that block with `@reference` pointing to `src/styles/global.css` to reuse the theme without emitting another Tailwind entry.
- Keep theme tokens, base defaults, shared presentation classes, named Vue transitions, keyframes, and reduced-motion handling in `src/styles/global.css`. Keep feature-specific selectors inside their owning components; avoid separate feature stylesheets or extracting every small utility combination.
- Prefer semantic theme utilities such as `bg-panel`, `text-main`, `text-muted`, and `border-line` so light and dark themes share one style definition. Use short semantic classes for composed styles and state objects such as `:class="{ active: isActive }"`; keep any inline utilities complete and statically discoverable.
- Use component library theme overrides for supported control sizing. Reserve important utilities for overriding the library's unlayered styles or explicitly suppressing competing component transitions. Retain semantic class hooks when tests or component behavior need them.
- Use canonical Tailwind utilities when they express the same style: `w-58` instead of `w-[232px]`, for example. ESLint checks template classes and all `@apply` rules, including scoped Vue styles, for canonical names, official ordering, duplicates, conflicts, and deprecated utilities. The canonical conversion assumes the application's fixed 16px root font size; update both the base style and lint settings if that changes. Keep arbitrary values when no equivalent utility exists. Prettier controls wrapping so lint fixes do not expand templates into long class lists.

## TypeScript

- Enable strict checking and retain noUncheckedIndexedAccess, unused local/parameter checks, and switch fallthrough checks.
- Treat runtime input as `unknown` until Zod validates it. Type assertions do not replace validation.
- Specify parameter types for public functions and module contracts. Infer schema result types with `z.infer` instead of maintaining duplicate field definitions.
- Use separate `import type` declarations. Group third-party imports, project modules, and type imports in that order. Put stylesheet side-effect imports first.
- Prefer const; use let only when reassignment is needed. Always use braces for conditionals and loops.
- Arrow functions are suitable for simple transformations. Prefer named functions for state changes and error-handling actions.
- Keep IDs as strings. Never convert upstream large IDs into unsafe numbers.
- Prefer native URL, Set, Map, and fetch APIs. Do not wrap a clear, small implementation in an unnecessary general-purpose framework.

## Formatting and Comments

Use two-space indentation, UTF-8, and LF line endings. EditorConfig and Prettier maintain these conventions. Put Vue attributes on separate lines and ignore HTML whitespace sensitivity to prevent closing tags from becoming crowded. Keep text that must remain continuous, such as the brand name, in a continuous text node or an explicitly preserved markup fragment.

Use blank lines to separate imports, state, derived values, actions, and lifecycle hooks. Inside functions, separate validation, computation, and state updates. ESLint requires spacing after imports, around function/block statements, and before returns. Separate major template regions and CSS rule blocks with blank lines.

Comments explain business rules, constraints, or non-obvious decisions: large string IDs, full-episode matching, download preparation, and streaming downloads. Do not repeat what the code already says or comment every ordinary variable.

## Verification

Prioritize boundaries that affect user results: request races and cancellation, damaged storage and denied writes, quality fallback, actual selection events, download preflight, and media target restrictions. Directory moves, ordinary copy changes, and formatting do not need tests that duplicate the implementation.

Verify interface changes in a browser, including narrow screens. Use HEAD or small Range requests to validate media delivery without downloading full episodes.

## References

Apply the conventions relevant to this project from the following sources. Project configuration is authoritative for formatting.

- [Vue Style Guide](https://vuejs.org/style-guide/)
- [Vue Composables](https://vuejs.org/guide/reusability/composables.html)
- [Vue Composition API with TypeScript](https://vuejs.org/guide/typescript/composition-api.html)
- [Tailwind CSS with Vite](https://tailwindcss.com/docs/installation/using-vite)
- [Tailwind Styling with Utility Classes](https://tailwindcss.com/docs/styling-with-utility-classes)
- [TypeScript Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html)
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html)
- [Prettier HTML Whitespace Sensitivity](https://prettier.io/docs/options#html-whitespace-sensitivity)
- [ESLint Stylistic Padding Rules](https://eslint.style/rules/padding-line-between-statements)
