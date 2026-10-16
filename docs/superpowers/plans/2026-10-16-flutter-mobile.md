# Flutter Mobile Client Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for continuous execution. Independent platform/data tasks may use superpowers:dispatching-parallel-agents after the shared contracts exist. Steps use checkbox syntax to record actual completion.

**Goal:** Deliver the complete Android/iOS Flutter client described by the approved specification, preserving the existing clients and unrelated work.

**Architecture:** A standalone Flutter application under `flutter/` connects directly to the upstream APIs. Riverpod controllers consume pure repository contracts; Drift repositories and native playback, background-transfer, and file adapters own effects. Shared JSON fixtures verify parity with the existing clients.

**Tech Stack:** Flutter stable 3.47.6 / Dart 3.13.5, Material 3, Riverpod, go_router, Dio, Drift, Freezed/json_serializable, better_player_plus, background_downloader, cached_network_image, path_provider and share_plus. Resolve mutually compatible stable package versions and commit `pubspec.lock`.

**Spec:** [Flutter Mobile Client Design](../specs/2026-10-16-flutter-mobile-design.md).

## Global Constraints

- Support Android 10/API 29 and newer, and iOS 15 and newer, on phones and tablets; report actual platform coverage separately.
- Use application identifiers `dev.sctvdl.flutter`, package `sctv_dl_mobile`, and Chinese application label `蜀台回看`.
- All domain IDs are decimal strings; reject upstream numeric IDs above `9007199254740991`.
- Preserve quality mapping, fallback, full-episode recognition, accepted snapshots, cancellation plus stale-response rejection, media headers/allowlist, and delayed player disposal.
- Keep user/runtime state separate, use actual transfer progress, and keep queued work native while Dart is suspended.
- Preserve unrelated Kotlin work. The requested first commit contains only the Flutter specification, implementation plan, and their README navigation.
- The user explicitly requested plan commit followed by implementation. Execute without another plan-approval prompt. Subsequent implementation commits are deferred unless separately requested.
- Write documentation, comments, and tests in English; retain Chinese product copy and programme names.

## Review Focus

1. A late archive response after a date/programme change must neither replace displayed content nor change a player's pinned selection; Task 3 tests both keys and disposal.
2. The OS may report completion while publication/export fails; Task 5 keeps a recoverable local file and does not announce a public completed file prematurely.
3. A transfer callback from an older attempt, including completion after cancellation/retry, must not revive or corrupt the replacement; Task 5 tests attempt identity and snapshot races.
4. Cancelling interactive back or exiting PiP must retain exactly one usable session and restore the right route/system UI; Tasks 2 and 6 test session ownership and native restoration.
5. iOS sandbox paths and native job IDs can change across launch/restore; Tasks 3 and 5 resolve relative file references and reject unowned runtime jobs.

## Execution and Evidence

Use the current checkout on a feature branch so uncommitted native UI work remains available and unchanged; new application code is isolated under `flutter/`. Record implementation decisions and test commands in `.superpowers/sdd/2026-10-16-flutter-mobile/progress.md`. Keep a final concise verification record in `flutter/README.md` or an owning validation document. Do not claim unavailable device, background, signing, or remote-CI checks as passed.

### Task 1: Portable Scaffold and Shared Business Contracts

**Files:** Create `flutter/pubspec.yaml`, lockfile, native hosts, `analysis_options.yaml`, `AGENTS.md`, `lib/domain/programmes/{programme,programme_policy,programme_repository}.dart`, `lib/domain/settings/{preferences,user_repository}.dart`, `lib/domain/playback/{playback_backend,history_repository}.dart`, `lib/domain/downloads/{download_task,download_repository}.dart`, and corresponding `test/domain/` tests. Modify root ignore/discovery configuration only to exclude generated Flutter products.

**Interfaces:** Produce immutable `Programme`, `BroadcastDate`, `ProgrammeContent`, `ContentRef`, `VideoQuality`, `Preferences`, `ViewingEntry`, `DownloadTask`, and `DownloadBatchResult`; scoped request cancellation; repository/player/transfer contracts consumed by Tasks 2–7. Keep contracts independent of Flutter widgets, HTTP, and SQLite. `ContentRef` contains programme/date/content IDs; media selection always reports requested and actual quality.

- [ ] Bootstrap Android/iOS hosts with `flutter create`, set product targets/identifiers, resolve stable dependencies, and remove the generated counter demo.
- [ ] Write domain tests for unsafe IDs, date deduplication, quality fallback and URL deduplication, exact full-episode matching, publication ordering, media-policy fixtures, safe Unicode filenames, and history completion/resume rules. A missing policy or deliberately absent result must fail observably.
- [ ] Run `flutter test test/domain`; expected RED from missing domain behaviour, then implement the contracts and named pure policies and repeat until GREEN.
- [ ] Verify formatting, `flutter analyze --fatal-infos`, and `flutter test`; expected no analysis errors and all domain tests passing.

### Task 2: Native Player and Transfer Capability Integration

**Files:** Create `lib/platform/playback/`, `lib/platform/downloads/`, `lib/platform/files/`, `test/platform/`, and `integration_test/native_capabilities_test.dart`; configure Android manifests/Gradle and iOS project/Info.plist/AppDelegate.

**Interfaces:** Consume Task 1 models. Produce `PlaybackBackend` sessions with initialize/play/pause/seek/speed/source-switch/PiP/dispose and observable snapshots; `TransferGateway` enqueue/query/events/pause/resume/cancel with caller-assigned attempt IDs; file capabilities with typed relative-path/content-URI locations and publication/export/open/share/delete operations.

- [ ] Write fake-backend controller tests and controlled native-media integration tests for headers, paused initialization, local playback, source-switch position/intent, PiP ownership, idempotent disposal, relative file lookup, and unsupported capabilities. Run them before completing each adapter.
- [ ] Integrate better_player_plus behind the playback contract; disable package-owned automatic lifecycle/disposal when application session ownership must control it. Reject unsupported media before opening. Verify or repair redirect handling at the native boundary without introducing an arbitrary URL relay.
- [ ] Integrate background_downloader using native holding queues, durable task IDs, configured notifications, effective network policy, and long-transfer support. Configure Files/scoped-storage handling and media exclusion from backup. Do not implement a second Dart transfer queue.
- [ ] Run platform tests plus controlled real decode/transfer/file journeys on available disposable Android/iOS devices. Expected: headers reach fixtures, native tasks/files match actual results, and every unavailable environment is recorded explicitly. Keep implementation work proceeding where device evidence is unavailable.

### Task 3: Validated Upstream, Drift Persistence, and Cache Acceptance

**Files:** Create `lib/data/database/`, `lib/data/programmes/`, `lib/data/settings/`, `lib/data/playback/`, and `test/data/` tests; add `shared/fixtures/` examples only when a cross-language rule is missing.

**Interfaces:** Implement Task 1 `ProgrammeRepository`, `UserRepository`, and `HistoryRepository`. Expose cached reads separately from refresh for catalogue/dates/contents, durable preferences/favourites/history streams, and a runtime task store used by Task 5. Store successful empty snapshots and cache keys explicitly. Native handles remain outside repositories' public models.

- [ ] Write tests using local HTTP servers and disposable SQLite databases: bounded malformed/business failures, guest identity creation, media/header separation, no redirects, late cancelled replies, cross-key snapshots, fetched-empty cache, failed refresh retention, failed saves, schema migration, 500-entry history retention, and cache cleanup preserving user/tasks.
- [ ] Run the focused tests and observe RED. Implement bounded Dio clients, persisted installation identity, parsing/normalization and Drift user/runtime databases, then repeat until GREEN.
- [ ] Implement application refresh state that distinguishes accepted and pending snapshots. Test changed/empty acceptance, retry without acceptance, and pinned playback selection remaining unchanged while a cache refresh completes.
- [ ] Run `flutter test test/data test/domain` and the complete `flutter test`; expected green suites and disposable fixture cleanup.

### Task 4: Adaptive Application Shell, Catalogue, Archive, and Settings

**Files:** Create `lib/app/{bootstrap,providers,router,app}.dart`, `lib/design/`, `lib/features/programmes/`, `lib/features/settings/`, `lib/main.dart`, and corresponding feature/widget tests.

**Interfaces:** Compose Task 3 repositories through Riverpod and go_router. Feature entry points consume immutable selections and callbacks; app navigation connects features. Retain primary branches and independent library-tab state. Pass accepted `ContentRef` and a pinned selection to the player/download workflows.

- [ ] Write widget/controller tests for startup settings, independent searches/scroll, favourites without unexpected reordering, manual exploration, cold/empty/error/offline screens, update acceptance, available dates, batch selection/back, quality-sheet dismissal, no-media cards, and preference persistence.
- [ ] Run tests to observe the missing screens/actions fail. Implement themed three-destination navigation, all/favourites/history tabs, adaptive cards, archive date sheets and ordering, selection controls, settings groups, and explicit feedback.
- [ ] Add phone/tablet and 200% text cases in both themes, reduced motion, keyboard search focus, and semantics assertions. Expected: no layout exceptions, inaccessible action targets, or unintended navigation/requests.
- [ ] Run `flutter test test/features/programmes test/features/settings` and the whole suite; keep live browser/mobile upstream smoke checks distinct from stub tests.

### Task 5: Durable Download Workflow and Task Management

**Files:** Create `lib/data/downloads/`, `lib/features/downloads/`, download controller/reconciliation tests and `integration_test/downloads_test.dart`.

**Interfaces:** Consume Task 2 `TransferGateway`/file adapter and Task 3 runtime task store. Implement `DownloadRepository` start/observe/pause/resume/cancel/retry/remove/delete/publish/open/share operations. Native events carry attempt identity; UI state exposes actual bytes, nullable totals, effective network policy, and typed waiting/errors.

- [ ] Write regression tests for duplicate active submissions, cancellation during preparation/enqueue, partial batches, stale-attempt callbacks, subscribe-before-snapshot ordering, terminal-state regression, restart recovery, ambiguous/missing native tasks, unsupported resume, ignored Range, unknown length, and externally deleted files.
- [ ] Run focused tests and observe RED; implement durable reservation before enqueue, two-transfer native concurrency, independent per-file results, bounded retries, reconciliation, and guarded state transitions.
- [ ] Test publication failure separately from transfer failure. Implement Android public Downloads publication with recoverable private completion, and iOS Documents/Files/export flows with relative locations. Dismissed export and failed deletion must preserve truthful state.
- [ ] Build task sections/actions, network/status labels, terminal removal versus explicit file deletion, local playback navigation, and notification routing. Confirm callbacks are observed across pages and cleaned up at application disposal.
- [ ] Run full Dart tests and native fixture download journeys: suspend/relaunch, long transfer, network loss, pause/resume, publication/export, and file removal. Record tested platforms and lifecycle modes separately.

### Task 6: Complete Playback UI, Lifecycle, and Viewing History

**Files:** Create `lib/features/player/`, `test/features/player/`, and `integration_test/playback_test.dart`; connect the app's playback host and history routes.

**Interfaces:** Consume Task 2 backend, Task 3 history/preferences, and Task 5 downloads. `PlaybackController` owns a pinned online/local input, actual variant selection, immutable player state, timers and one native session. PiP ownership may outlive the visible route; committed route disposal waits for transition completion.

- [ ] Write tests for paused start, remembered quality/fallback, stale initialization, quality-switch rollback, source position/speed/intent retention, controls timeout, lifecycle pause versus explicit PiP, cancelled return, delayed cleanup after reopening, and history save throttling/completion.
- [ ] Run RED, then implement accessible controls, bounded upward menus, timeline, fullscreen and PiP, scrollable context/download entry, errors/retry, and idempotent route/session cleanup.
- [ ] Connect recent-viewing rows and local playback to the same content history identity. Persist progress every five seconds at most and at pause/seek/background/exit; resume remains paused.
- [ ] Run the whole suite, native controlled decode tests, and sampled live media HEAD/Range/playback/seek/source switching. Expected: no whole-video verification download, duplicate sessions, unwanted autoplay, or leaked orientation/audio focus.

### Task 7: Platform Polish, Accessibility, and Regression Acceptance

**Files:** Extend feature/device tests and native host configuration; create `flutter/README.md` and an owning validation record with exact evidence.

**Interfaces:** Exercise the complete app with fixture repository/adapter overrides and native integrations. Only platform composition contains device-specific decisions; feature capabilities remain typed.

- [ ] Add missing failing regressions for large Chinese titles, unknown dates/duration, keyboard/back interactions, both themes, large text, interrupted animations, process restoration, notification navigation, file permissions, and missing storage.
- [ ] Complete platform-specific fixes and rerun affected/full suites. Run TalkBack/VoiceOver and narrow/expanded/landscape inspection on the available disposable runtimes, restoring their preferences afterward.
- [ ] Run format, analysis, tests, release APK/AAB, and unsigned iOS release compilation. Install and exercise release-mode browse/archive/paused-player/download/local-playback journeys where supported.
- [ ] Record results by target, mode, OS and device. List unavailable minimum-OS/physical-device/background/signing checks without marking them passed. Restore preview processes and remove fixture artifacts.

### Task 8: CI, Dependency Maintenance, Documentation, and Final Review

**Files:** Create `.github/workflows/flutter.yml`; update `.github/dependabot.yml`, `.gitignore`, `.prettierignore`, `vite.config.ts`, relevant lint/test-discovery configuration, root README, and Flutter documentation.

**Interfaces:** Keep existing Web/Android/Tauri commands working. Flutter CI uses the pinned SDK and lockfile, checks generated sources/format/analysis/tests, and compiles native releases separately from runtime acceptance.

- [ ] Add CI and pub dependency updates for `/flutter`; keep SDK paths, signing identities, generated products and local caches untracked. Exclude Flutter build/native output from existing root tooling without hiding relevant shared-contract tests.
- [ ] Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`, `flutter test`, Android release builds and unsigned iOS release compilation from `flutter/`; expected passing commands, with actual environment failures investigated and recorded.
- [ ] Run root `pnpm check` and `pnpm build` after shared/discovery changes; verify local documentation links and `git diff --check`.
- [ ] Use one fresh whole-change reviewer for contract, lifecycle, persistence, native-file and UI risks. Reproduce important findings with failing tests, fix them, and rerun the affected/full suites. Review the final diff for unrelated changes.
- [ ] Update this plan/spec status and durable documentation to match actual delivered features and verification. Leave implementation changes reviewable and uncommitted unless the user requests their commit.

## Plan Commit Gate

Before application implementation, run `pnpm format:check`, validate relative documentation links and `git diff --check`, then commit only `README.md`, this plan, and the Flutter specification using `docs: plan complete Flutter mobile client`. Inspect the commit's exact path list. No push or deployment is authorized.
