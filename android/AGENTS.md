# Android Agent Instructions

These instructions apply inside `android/`. Read [README](README.md) and the relevant section of [Client Design](../docs/android-client-design.md) before changing native behaviour.

## Ownership

- `app` owns application setup, typed Navigation 3 routes, global preferences/download feedback, foreground reconciliation, and the Activity playback host.
- `feature:programmes` owns catalogue, favourites, broadcast archives, accepted resource state, and their presentation components.
- `feature:downloads`, `feature:settings`, and `feature:player` own their destination state, Route entry points, screens, and actions.
- `core:domain` contains Kotlin-only models, repository contracts, and programme/download policies, grouped by subject. It has no Android dependencies.
- `core:data` owns HTTP validation, Room, DataStore, DownloadManager, and restart reconciliation. Implementation packages follow the owning feature and remain internal; public qualifiers and the manifest receiver are platform integration contracts.
- `core:design` owns generic theme tokens and stateless Compose primitives, without domain or feature dependencies. Keep the module name `design`.
- `core:ui` owns shared application presentation: covers/transitions, download quality/outcome text, cached errors, and the settings-to-theme adapter.
- `core:player` owns Media3 sessions, playback models/controller, surface, and native controls. `feature:player` owns destination lifetime; `app` implements its `PlaybackHost` contract.

Features never depend on sibling features, `app`, or `core:data`. Core modules never depend on features or `app`. Expose feature Route entry points and small immutable cross-module contracts; keep screens, ViewModels, and component helpers internal. `checkModuleDependencies`, included in `check`, verifies configured Gradle project edges, including test dependencies. Shared JVM fakes live in domain test fixtures and are consumed only by tests. Android/Compose/Hilt defaults live in `build-logic`; versions remain in the version catalogue.

Preserve the database filename, schema/version/identity, DataStore keys and enum strings, application ID, saved-state keys, and serialized `AppRoute` names when moving source packages. Keep accepted playback selections at the app root across navigation entries; features exchange callbacks rather than importing each other. Retain expanded catalogue/favourite positions in the root programme library scope, with separate grid controllers for simultaneously rendered navigation entries.

## Kotlin and Compose

Use explicit imports, four spaces, and a 120-column limit. Spotless with ktlint owns mechanical formatting. Annotated Composable functions use PascalCase. Other functions use camelCase. Documentation, comments, and test descriptions are English; product copy is Chinese.

Expose immutable `StateFlow` state and named UI actions. Use lifecycle-aware collection and `SavedStateHandle` for small restorable route/filter/selection/position state. Keep `Context`, activities, players, and file launchers outside ViewModels. Rethrow coroutine cancellation. A cancelled or stale request must not replace the current programme/date state.

Use Material 3 semantic colours, 48 dp touch targets, accessible labels, and adaptive layouts. Check both themes, keyboard interaction, 200% text, loading/empty/error states, and window resizing. Keep upstream titles intact. Never invent covers, durations, file sizes, or successful downloads.

### Readability

Follow the [Kotlin conventions](https://kotlinlang.org/docs/coding-conventions.html) and [Android Kotlin guide](https://developer.android.com/kotlin/style-guide), with this project's formatter configuration taking precedence for mechanical details.

- Separate functions, initializer blocks, and nested declarations with one blank line. Keep annotations and KDoc attached to their declaration. EditorConfig and Spotless explicitly enable ktlint's `blank-line-before-declaration` rule, including in tests and Gradle scripts.
- Group properties by responsibility: dependencies, backing state with its exposed state, request/lifecycle bookkeeping, and derived state. Separate these groups with one blank line; do not insert blank lines between every related property. Preserve initialization order when organizing declarations.
- Inside functions, separate guards, preparation, external work, and state/persistence updates when they form distinct steps. Keep each small cohesive operation together; avoid both dense blocks and a blank line after every statement.
- In composables, separate remembered/collected state, derived values and callbacks, effects, and rendered content. Keep each effect beside the lifecycle concern it owns. Do not move effect keys, state owners, or disposal timing for formatting.
- In `build-logic`, separate plugin application, extension configuration, version-catalog lookup, and dependency registration. Separate top-level Gradle DSL blocks with one blank line, and explain non-obvious plugin or dependency-version constraints.
- Use expression bodies for short expressions and simple delegates. Make multistep actions readable with normal blocks or multiline lambdas. Keep short argument lists and `catch` headers together; break long calls at argument or chain boundaries, not around a lone argument.
- Use descriptive names and named arguments when adjacent booleans, nullable values, or same-typed arguments are ambiguous. Name lambda parameters when nested `it` references obscure which object is being read or updated.
- Keep related methods and their helpers together in reading order. Extract a helper or component when it gives a substantial operation a useful name; do not introduce an abstraction just to shorten a file or satisfy an arbitrary line count.
- Apply the same grouping in tests: arrange fixtures, perform the action, then assert the outcome, with blank lines between these phases.

### Comments and Contracts

- Use KDoc on shared contracts and nontrivial state holders to explain caller obligations, return-value meaning, side effects, and lifecycle ownership that types and names do not convey. Link referenced declarations with KDoc syntax. Simple delegates, self-explanatory models, and every parameter do not need boilerplate documentation.
- Place concise `//` comments immediately before non-obvious decisions: cancellation/stale-response guards, accepted versus pending cache data, transaction/lock boundaries, download submission recovery, storage compatibility, and player disposal. Explain why the constraint exists and what would break if removed, rather than narrating the next statement.
- Keep comments accurate when code changes. Prefer a clear name or small helper when an explanation merely compensates for an opaque expression. Avoid section banners, commented-out code, and repeated comments on identical cancellation handling.
- During review, check semantic grouping and contract comments in addition to Spotless; a formatter pass alone does not establish readability. Readability cleanup must preserve saved keys, coroutine cancellation, request identity, UI copy, and lifecycle timing.

## Contracts

- IDs remain strings. Large numeric JSON IDs are rejected unless exactly representable within the upstream contract.
- `video` means standard quality; `videoStandard` means smooth quality. Distinct URLs determine available variants.
- Application-controlled HTTP clients disable redirects and validate upstream URLs. Media requests use the required Referer.
- Cache a validated successful empty response. Preserve cached data on refresh failures.
- Persist download preparation before system submission. Reserve active content/quality identity transactionally. Reconcile interrupted submissions by the planned unique destination; ambiguous matches require explicit user resolution.
- System byte/status queries determine progress. Unknown total length is indeterminate. No pause/resume action is exposed for platform downloads.
- Removing a history record preserves files. Cancelling an active platform job removes that job and its partial file. Validate completed content URIs before playback/open/share.
- Player startup is paused. Quality changes retain playback intent and position. Ordinary backgrounding pauses; explicit picture-in-picture may continue. Release only after the destination leave transition disposes the entry.
- Exclude cached metadata and runtime download IDs from backup. Keep machine paths, signing material, generated caches, and temporary memory limits out of tracked configuration.

## Verification

Use a separate, disposable, agent-owned AVD for emulator and instrumentation tests. Never reuse the user's everyday emulator unless the user explicitly authorizes that device. Select the agent-owned device explicitly for every ADB command and connected test run; do not run tests on all connected devices. Keep test app installations, display size/density changes, and other test settings on that AVD. Restore temporary settings and stop only processes started for testing; leave the user's emulators running and preserve their apps and data. Confirm restored display settings with both reported values and a screenshot before claiming restoration is complete.

Run from the repository root:

```powershell
android/gradlew.bat -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
android/gradlew.bat -p android connectedDebugAndroidTest
```

Use disposable fixtures for system downloads and media tests. Never download whole upstream episodes just to check transport. Validate live media using HEAD or a small Range request. Run `pnpm check` and `pnpm build` when shared Web/tooling files change. Review the diff and record actual checks and unavailable device coverage. Release remains unsigned until the user supplies a signing identity.
