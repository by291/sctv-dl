# Agent Instructions

These instructions apply throughout this repository. `sctv-dl` is a Vue/TypeScript Web app with one Node service for production assets, programme APIs, and MP4 streaming. The frontend lives at the repository root; runtime versions and commands are defined in `package.json`.

## Task Context

Read only the documents relevant to the change:

- [README](README.md): setup and commands.
- [Architecture](docs/architecture.md): module ownership, request and storage lifecycles, downloads, and player behaviour.
- [Deployment](docs/deployment.md): server configuration, hosting, and operations.
- [Upstream API](docs/upstream-api.md): response schemas, IDs, video variants, and proxy contracts.
- [Android Instructions](android/AGENTS.md): native module ownership, Kotlin/Compose readability, and Android checks.

## Working Conventions

- Write documentation, comments, test descriptions, and commit messages in English. Preserve Chinese UI copy and upstream programme names.
- Inspect Git status, preserve unrelated edits, and keep changes focused on the requested outcome.
- Reuse the existing Vue, Pinia, Naive UI, VueUse, Zod, Artplayer, and native platform capabilities before adding infrastructure.
- Use pnpm's shared store and portable configuration. Keep machine-specific paths and generated caches out of tracked files.
- Commit, push, or deploy when the user requests those actions.

## Code Style

Mechanical rules belong to `.editorconfig`, `.prettierrc.json`, `eslint.config.js`, and the TypeScript configurations. Run the existing tools instead of duplicating their rules.

- Separate imports, state, derived values, actions, and lifecycle hooks with blank lines. Separate validation, computation, and state updates inside functions. Comments explain business rules and non-obvious constraints.
- Use `<script setup lang="ts">`, followed by the template and optional scoped styles. Use PascalCase component filenames, `View` suffixes for pages, `useXxx` composables, typed component contracts, and stable string IDs as keys.
- Keep complex template expressions and multistep mutations in named actions or computed values. Respect feature ownership: shared modules must not depend on feature stores, and browser modules must not import `server/`.
- Use `@/` for internal browser imports. Keep programme API/model modules independent of consuming features and production server modules independent of `tooling/`. Within features, place pages in `views/`, business components in `components/`, and logic in its responsibility directory. Omit unused directories; keep tests beside their owners. See Architecture for the ownership map.
- Validate external input as `unknown` with Zod and infer schema types with `z.infer`. Keep IDs as strings, public functions typed, and type imports separate.
- The server executes TypeScript directly in Node. Use explicit `.ts` local imports and erasable syntax; avoid enums and parameter properties.
- Keep `shared/contracts/` platform-neutral. Browser imports use `@shared/`; Node imports use relative `.ts` paths. Compose concrete adapters in `src/platform/`; features must not import that composition layer, and Vue components must not import Tauri APIs.

### CSS and UI

- Use descriptive classes in templates and native CSS in the owning component's scoped stylesheet. Keep responsive rules in the same file with native `@media` conditions.
- Keep theme variables, base rules, shared presentation classes, named transitions, and reduced-motion handling in `src/styles/global.css`. Keep feature styles with their components. See [Web Styling](docs/styling.md) for ownership and cascade conventions.
- Use semantic theme variables such as `var(--panel)`, `var(--text)`, and `var(--line)`. Write explicit length units; use unitless values only where CSS defines them, such as line height or font weight.
- Prefer library theme overrides for supported sizing. Reserve `!important` for competing library styles, transition overrides, and accessibility rules. Use `:deep()` only for library-generated descendants.
- Preserve CSS diagnostics for global styles and Vue style blocks. Keep the base layer below component styles so reduced-motion important declarations retain priority.

Preserve the task's relevant contracts from Architecture and Upstream API. In particular, retain cancellation and stale-response guards, saved-settings compatibility, truthful browser download handoff, proxy restrictions, and player cleanup after the modal leave animation.

## Verification

Run commands from the repository root:

| Change                          | Checks                                                           |
| ------------------------------- | ---------------------------------------------------------------- |
| Application or server behaviour | `pnpm check` and `pnpm build`                                    |
| UI                              | The above plus browser verification at desktop and narrow widths |
| Documentation only              | `pnpm format:check`, local links, and referenced commands        |

Add meaningful regression coverage for behaviour changes. Tests are colocated as `*.test.ts`; tooling tests live in `tooling/`. Use disposable fixtures and stub upstream services. Do not add tests that duplicate copy or formatting, or run application tests/builds for documentation-only changes.

For UI changes, check affected themes, keyboard interaction, and loading/empty/error states. Validate media with HEAD or a small Range request. Restore temporary preview processes and browser preferences afterward.

## Documentation and Handoff

Keep each subject in its owning document, using the map in README. Update it when a contract, command, or behaviour changes. Extract reusable constraints from completed plans, then remove obsolete plans and execution checklists.

Review the diff for unrelated changes. Report what changed, what was actually verified, and any checks that could not run.

References: [Vue TypeScript](https://vuejs.org/guide/typescript/composition-api.html), [Vue Composables](https://vuejs.org/guide/reusability/composables.html), [Vue Scoped CSS](https://vuejs.org/api/sfc-css-features.html), [TypeScript Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html).
