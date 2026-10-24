# Agent Instructions

These instructions apply throughout this repository; platform `AGENTS.md` files supplement them within their directories. `sctv-dl` contains a Vue/TypeScript Web app, Tauri desktop app, Kotlin Android client, Flutter client and SwiftUI Apple client. The Web frontend lives at the repository root, with one Node service for assets, programme APIs and MP4 streaming. Web runtime versions and commands are defined in `package.json`; native setup belongs to each platform guide.

## Task Context

Read only the documents relevant to the change:

- [README](README.md): setup and commands.
- [Architecture](docs/architecture.md): module ownership, request and storage lifecycles, downloads, and player behaviour.
- [Deployment](docs/deployment.md): server configuration, hosting, and operations.
- [Upstream API](docs/upstream-api.md): response schemas, IDs, video variants, and proxy contracts.
- [Repository Maintenance](docs/maintenance.md): verification scope, CI, dependencies, and documentation ownership.
- [Android Architecture](docs/android.md): native product, data, and lifecycle contracts.
- [Flutter Architecture](docs/flutter.md): Flutter product, boundaries, and resource ownership.
- [Flutter Instructions](flutter/AGENTS.md): Dart/native-host conventions and checks.
- [Apple Architecture](docs/apple.md): SwiftUI navigation, storage, playback, downloads, and file ownership.
- [Apple Instructions](apple/AGENTS.md): Swift concurrency, lifecycle ownership, and native checks.
- [Android Instructions](android/AGENTS.md): native module ownership, Kotlin/Compose readability, and Android checks.
- [Desktop Development](docs/desktop.md): Tauri scaffold, shared contracts, native commands, and current integration limits.
- [Desktop Instructions](src-tauri/AGENTS.md): Rust ownership, readability, blocking work, and resource completion rules.

## Working Conventions

- Write documentation, comments, test descriptions, and commit messages in English. Preserve Chinese UI copy and upstream programme names.
- Inspect Git status, preserve unrelated edits, and keep changes focused on the requested outcome.
- Reuse the existing Vue, Pinia, Naive UI, VueUse, Zod, Artplayer, and native platform capabilities before adding infrastructure.
- Use pnpm's shared store and portable configuration. Keep machine-specific paths and generated caches out of tracked files.
- Commit, push, or deploy when the user requests those actions.

## Code Style

Use official language guidance and established ecosystem style guides to assess naming, API design and readability. Existing project code and instructions are not proof of good style. Platform instructions link their language references; repository formatter settings own mechanical choices.

For Web/Node code, mechanical rules belong to `.editorconfig`, `.prettierrc.json`, `eslint.config.js`, and the TypeScript configurations. Run the existing tools instead of duplicating their rules.

- Use `<script setup lang="ts">`, followed by the template and optional scoped styles. Use PascalCase component filenames, `View` suffixes for pages, `useXxx` composables, typed component contracts, and stable string IDs as keys.
- Keep complex template expressions and multistep mutations in named actions or computed values. Respect feature ownership: shared modules must not depend on feature stores, and browser modules must not import `server/`.
- Use `@/` for internal browser imports. Keep programme API/model modules independent of consuming features and production server modules independent of `tooling/`. Within features, place pages in `views/`, business components in `components/`, and logic in its responsibility directory. Omit unused directories; keep tests beside their owners. See Architecture for the ownership map.
- Validate external input as `unknown` with Zod and infer schema types with `z.infer`. Keep IDs as strings, public functions typed, and type imports separate.
- The server executes TypeScript directly in Node. Use explicit `.ts` local imports and erasable syntax; avoid enums and parameter properties.
- Keep `shared/contracts/` platform-neutral. Browser imports use `@shared/`; Node imports use relative `.ts` paths. Compose concrete adapters in `src/platform/`; features must not import that composition layer, and Vue components must not import Tauri APIs.

### Readability and Responsibilities

- Give each module one coherent responsibility and each function one main level of abstraction. Extract a named step when it hides a distinct rule or workflow; split files when concerns change independently, rather than to meet a line-count limit.
- In simple setup blocks, group component contracts, state, derived values, actions, and lifecycle hooks in that order. For multiple concerns, keep each concern's related state and actions together. Use blank lines at meaningful phase boundaries inside functions, including validation, computation, external calls, and state updates.
- Name state by its meaning: distinguish connection versions, snapshot revisions, local edits, pending counts, and disposal flags. Name actions after their outcome and predicates after the question they answer. Move repeated business decisions and complex template conditions into named functions or computed values.
- Comments explain why a rule exists, what makes an operation safe, or who owns cleanup. Document cancellation versus stale-result rejection, subscription/load ordering, settings compatibility, partial failures, and delayed player disposal where those constraints are implemented. Avoid narrating assignments or adding comments to satisfy a quota.
- Express related states with typed results or discriminated unions instead of parallel flags, non-null assertions, or repeated property probing. Reuse schema-derived contract types; preserve useful local type inference.
- Keep side effects with their lifecycle owner. Requests, listeners, subscriptions, and player sessions need a visible cleanup path. Handle asynchronous failures at the owning boundary, preserve useful causes, and explain intentional best-effort cleanup when errors are ignored.
- Organize tests into setup, action, and observable assertions. Cover business boundaries and lifecycle races; do not test source spelling, formatting, or private decomposition.

### Server, Shared Contracts, and Tooling

- Keep HTTP input errors independent of business services and response mapping. Handlers coordinate validation, service execution, and replies; header policies and business decisions have named owners.
- Keep request listeners, deadlines, cancellation, and stream cleanup with their lifecycle owner. Distinguish response-header deadlines from body reception limits and long-lived media streaming; preserve backpressure and disconnect cancellation.
- Shared contracts must not depend on build/test tooling. Keep schema types and protocol semantics together, including nullable fields, epoch/revision/attempt guards, and saved-data defaults. Keep tests beside the contract they exercise.
- Release bootstrap commands that run before dependency installation use Node-only APIs and explicit guards for unknown JSON input. Do not replace runtime validation with type assertions or add a dependency to these entrypoints.
- Workflows orchestrate commands; platform signing scripts own credential validation, temporary files, and certificate cleanup. Document ownership transfer between setup and post-build cleanup, preserve original failures during rollback, and never print credentials.

### CSS and UI

- Use descriptive classes in templates and native CSS in the owning component's scoped stylesheet. Keep responsive rules in the same file with native `@media` conditions.
- Keep theme variables, base rules, shared presentation classes, named transitions, and reduced-motion handling in `src/styles/global.css`. Keep feature styles with their components. See [Web Styling](docs/styling.md) for ownership and cascade conventions.
- Use semantic theme variables such as `var(--panel)`, `var(--text)`, and `var(--line)`. Write explicit length units; use unitless values only where CSS defines them, such as line height or font weight.
- Prefer library theme overrides for supported sizing. Reserve `!important` for competing library styles, transition overrides, and accessibility rules. Use `:deep()` only for library-generated descendants.
- Preserve CSS diagnostics for global styles and Vue style blocks. Keep the base layer below component styles so reduced-motion important declarations retain priority.

Preserve the task's relevant contracts from Architecture and Upstream API. In particular, retain cancellation and stale-response guards, saved-settings compatibility, truthful browser download handoff, proxy restrictions, and player cleanup after the modal leave animation.

## Verification

Choose checks from [Verification by Change](docs/maintenance.md#verification-by-change). Web/Node commands run from the repository root; native commands use the working directory documented by their platform guide. Native-only changes do not automatically require the Web suite.

- Web/Node behaviour: run `pnpm check` and `pnpm build`. Web UI also needs desktop/narrow browser checks, themes, keyboard interaction and loading/empty/error states.
- Native behaviour: follow the platform README and AGENTS instructions. Add Web checks when browser adapters, shared runtime contracts or Web build/tooling behaviour changes.
- Workflow changes: run `pnpm ci:lint`, formatting and relevant tooling tests. CI uses checks, tests and compilation that do not require a booted simulator/emulator, connected device or native GUI interaction. Keep native UI/device acceptance as explicit local checks.
- Documentation only: run `pnpm format:check`, `pnpm docs:check` and `git diff --check`; inspect referenced scripts/configuration for command accuracy. Do not run application builds or device tests merely because their commands appear in documentation.

Add meaningful regression coverage for behaviour changes. Web/Node tests are colocated as `*.test.ts`, with root tooling tests in `tooling/`; native tests follow platform ownership. Use disposable fixtures and stub upstream services. Do not test source spelling, formatting or private decomposition.

Validate live media with HEAD or a small Range request. Restore temporary preview processes and browser preferences afterward. Keep automated tests, local device acceptance, hosted CI and signed distribution as separate claims.

## Documentation and Handoff

Keep each subject in its owning document, using the map in README. Update it when a contract, command, or behaviour changes. Extract reusable constraints from completed plans, then remove obsolete plans and execution checklists. Keep reusable verification procedures in platform guides and per-run evidence in ignored build outputs; removing a plan is not evidence that its checks passed.

Review the diff for unrelated changes. Report what changed, what was actually verified, and any checks that could not run.

References: [Vue TypeScript](https://vuejs.org/guide/typescript/composition-api.html), [Vue Composables](https://vuejs.org/guide/reusability/composables.html), [Vue Scoped CSS](https://vuejs.org/api/sfc-css-features.html), [TypeScript Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html).
