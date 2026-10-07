# Agent Instructions

These instructions apply throughout this repository. `sctv-dl` is a Vue/TypeScript Web app with one Node service for production assets, programme APIs, and MP4 streaming. The frontend lives at the repository root; runtime versions and commands are defined in `package.json`.

## Task Context

Read only the documents relevant to the change:

- [README](README.md): setup and commands.
- [Architecture](docs/architecture.md): module ownership, request and storage lifecycles, downloads, and player behaviour.
- [Deployment](docs/deployment.md): server configuration, hosting, and operations.
- [Upstream API](docs/upstream-api.md): response schemas, IDs, video variants, and proxy contracts.

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
- Validate external input as `unknown` with Zod and infer schema types with `z.infer`. Keep IDs as strings, public functions typed, and type imports separate.
- The server executes TypeScript directly in Node. Use explicit `.ts` local imports and erasable syntax; avoid enums and parameter properties.

### Tailwind and UI

- Keep short utilities in templates. Compose long, responsive, or repeated styles in the owning component's scoped `@apply` rules, using `@reference` with the correct relative path to `src/styles/global.css`.
- Keep theme tokens, base rules, shared presentation classes, named transitions, and reduced-motion handling in the global entry. Keep feature styles with their components.
- Use semantic theme utilities such as `bg-panel`, `text-main`, and `border-line`. Keep inline classes complete and statically discoverable; prefer library theme overrides for supported sizing. Reserve important utilities for competing library styles.
- Preserve Tailwind diagnostics and canonical-class checks for templates and `@apply`. Canonical conversion assumes a 16px root font size; changing it requires updating base styles and lint settings together.

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

References: [Vue TypeScript](https://vuejs.org/guide/typescript/composition-api.html), [Vue Composables](https://vuejs.org/guide/reusability/composables.html), [Tailwind Utilities](https://tailwindcss.com/docs/styling-with-utility-classes), [TypeScript Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html).
