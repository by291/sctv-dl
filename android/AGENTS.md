# Android Agent Instructions

These instructions apply inside `android/`. Read [README](README.md) and the relevant section of [Client Design](../docs/android-client-design.md) before changing native behaviour.

## Ownership

- `app` owns navigation, feature ViewModels, screen state, platform activity lifecycle, and feature Compose screens.
- `core:domain` contains Kotlin-only models, repository contracts, and programme/download policies. It has no Android dependencies.
- `core:data` owns HTTP validation, Room, DataStore, the system download gateway, and restart reconciliation.
- `core:design` owns theme tokens and reusable stateless Compose components. It must not depend on feature ViewModels or repositories.
- `core:player` owns the destination-scoped Media3 session, playback controller, and native video controls.

## Kotlin and Compose

Use explicit imports, four spaces, and a 120-column limit. Spotless with ktlint owns mechanical formatting. Annotated Composable functions use PascalCase. Other functions use camelCase. Documentation, comments, and test descriptions are English; product copy is Chinese.

Expose immutable `StateFlow` state and named UI actions. Use lifecycle-aware collection and `SavedStateHandle` for small restorable route/filter/selection/position state. Keep `Context`, activities, players, and file launchers outside ViewModels. Rethrow coroutine cancellation. A cancelled or stale request must not replace the current programme/date state.

Use Material 3 semantic colours, 48 dp touch targets, accessible labels, and adaptive layouts. Check both themes, keyboard interaction, 200% text, loading/empty/error states, and window resizing. Keep upstream titles intact. Never invent covers, durations, file sizes, or successful downloads.

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

Run from the repository root:

```powershell
android/gradlew.bat -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
android/gradlew.bat -p android :app:connectedDebugAndroidTest :core:data:connectedDebugAndroidTest
```

Use disposable fixtures for system downloads and media tests. Never download whole upstream episodes just to check transport. Validate live media using HEAD or a small Range request. Run `pnpm check` and `pnpm build` when shared Web/tooling files change. Review the diff and record actual checks and unavailable device coverage. Release remains unsigned until the user supplies a signing identity.
