# Apple Downloads and Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable background downloads, reliable local files and platform acceptance for the complete client.

**Architecture:** A short serialized state lane owns task transitions. Native transfers and file effects run through explicit ports outside that lane, with attempt/revision guards on every final commit.

**Tech Stack:** Background URLSession, GRDB, security-scoped bookmarks, SwiftUI, Swift Testing and XCTest.

**Spec:** [Approved design](../specs/2026-10-22-apple-client-design.md); [plan index](2026-10-22-apple-client.md). Prerequisites: [A](2026-10-22-apple-media.md) and [B](2026-10-22-apple-browsing.md).

## Global Constraints

Inherit every constraint and verification convention in the index. Download batches accept at most 100 distinct items. Each retry receives a new attempt. Publication is separate from transfer completion. New network preferences affect new tasks only. Missing local playback never silently falls back to the network. Signed distribution requires separate authorization.

## Review Focus

Ambiguous enqueue and replaced-attempt callbacks belong to C1/C2. Temporary-file expiry during a callback belongs to C2. Revoked external access, missing completed files, duplicate filenames and insufficient space belong to C3. Minimum-OS and real-device coverage belong to C4.

## Task C1: Durable download commands and state transitions

**Files:**

- Create: `Sources/SCTVCore/Downloads/{DownloadTask.swift,DownloadCommand.swift,DownloadService.swift,DownloadPreparation.swift,DownloadRepository.swift,FileDestination.swift,DownloadedFile.swift}`.
- Create: `Sources/SCTVData/Storage/DownloadMigrations.swift`, `Sources/SCTVData/Downloads/SQLiteDownloadRepository.swift`.
- Create: `Sources/SCTVDownloads/Queue/{DownloadCoordinator.swift,DownloadTransition.swift,DownloadReconciler.swift}`.
- Test: `Tests/SCTVDownloadsTests/{DownloadTransitionTests.swift,DownloadRecoveryTests.swift}`.
- Modify: package targets to add SCTVDownloads and database factory/runtime migrations from B1.

**Interfaces:**

- `DownloadTask: Sendable` holds UUID task/attempt IDs, revision, ContentRef and pinned metadata, actual quality, network policy, native correlation, destination reference and state.
- `DownloadState` cases: queued, transferring, paused, publishing, completed, cancelled, interrupted, transferFailed, publicationFailed, missingFile; associated values retain relevant bytes, recovery references and errors.
- `DownloadCommand` contains action, task UUID and expected attempt UUID; actions distinguish pause/resume/retry/publication retry/cancel/file deletion/record removal.
- `DownloadService: Sendable`: `start(_ requests: [DownloadRequest]) async -> DownloadBatchResult`, `perform(_ commands: [DownloadCommand]) async -> DownloadBatchResult`, `updates() async -> AsyncStream<DownloadSnapshot>`, `reconcile() async throws`.
- `DownloadRequest` pins content metadata, prepared MediaSource, network policy and destination. `DownloadBatchResult` returns accepted IDs and per-item typed failures. `DownloadSnapshot` contains monotonic revision and ordered tasks, including removals through authoritative replacement snapshots.
- `FileDestination: Codable, Sendable` has applicationManaged and external(bookmarkID: UUID) cases. `StagedFile` carries task/attempt IDs and a sandbox-relative staging path. `PublishedFile` carries destination, relative filename, byte size and stable file identity. Define these core values in C1 so later publication does not force a dependency on SCTVDownloads.
- `DownloadPreparation.prepare(contents: [ProgrammeContent], programme: Programme, broadcast: BroadcastDate, requestedQuality: VideoQuality, productVersion: String) -> DownloadPreparationResult` applies validated-source, actual-quality and safe-filename rules to pinned records; the result contains prepared items plus per-item failures. Inject the resulting values into DownloadRequest with the current destination and policy.
- `DownloadRepository` is a core protocol for transactional reservations and guarded state changes; the SCTVData implementation owns SQL, and SCTVDownloads never imports GRDB.

- [ ] Write `DownloadTransitionTests.oldAttemptCannotMutateRetry`, `reservesContentAndActualQualityOnce`, and `batchRejectsMoreThan100`. Assert stale command outcomes and exactly one reservation for concurrent starts. Write `DownloadRecoveryTests.ambiguousEnqueueDoesNotDuplicate` and verify `#expect(nativeEnqueueCount == 1)` after recovery.
- [ ] Run `swift test --package-path apple/Packages/SCTVKit --filter 'DownloadTransitionTests|DownloadRecoveryTests'`; expect the named transition/reservation tests to fail.
- [ ] Define the repository port's concrete transaction methods around `reserve(_ request: DownloadRequest) async throws -> DownloadTask` and `commit(_ task: DownloadTask, expectedRevision: UInt64, expectedAttempt: UUID) async throws -> Bool`; implement them in SQLiteDownloadRepository. Enforce active content/actual-quality uniqueness in the database, not only in UI state. Persist accepted context before enqueue.
- [ ] Implement short serialized transitions and per-task effect ownership. Retry changes the attempt; cancellation/cleanup cannot race a replacement task's publication. Subscribe before snapshots and reconcile native state with persisted correlation. Do not hold SQL transactions or the transition lane during file operations.
- [ ] Run both suites including two-observer/window cases and partial batch failures. Review boundary: `feat(apple): add durable download state and recovery` (commit only if authorized).

## Task C2: Background URLSession and staging lifecycle

**Files:**

- Create: `Sources/SCTVCore/Downloads/{TransferDriver.swift,TransferEvent.swift}`.
- Create: `Sources/SCTVDownloads/Transfer/{BackgroundSessionDriver.swift,BackgroundSessionDelegate.swift,TransferCorrelation.swift,ResumeDataStore.swift}` and `Sources/SCTVDownloads/Files/DownloadStagingStore.swift`.
- Create: `apple/Apps/iOS/BackgroundSessionEvents.swift`, `apple/Apps/macOS/BackgroundSessionEvents.swift`.
- Test: `Tests/SCTVDownloadsTests/{BackgroundTransferTests.swift,StagingRecoveryTests.swift}`, `apple/Tests/{iOS,macOS}/BackgroundDownloadAcceptanceTests.swift`.
- Modify: native delegates/entitlements and app-scoped service composition; extend the A2 fixture server for interrupted downloads.

**Interfaces:**

- `TransferDriver: Sendable`: `enqueue(_ task: DownloadTask) async throws -> NativeTransferID`, `cancel(_ id: NativeTransferID) async throws`, `pause(_ id: NativeTransferID) async throws -> ResumeReference?`, `resume(_ task: DownloadTask, from reference: ResumeReference) async throws -> NativeTransferID`, `snapshot() async throws -> [NativeTransfer]`, `events() async -> AsyncStream<TransferEvent>`.
- `NativeTransferID` identifies session plus native task; `NativeTransfer` contains correlation and system state. `TransferEvent` includes attempt identity and progress/staged-completion/failure payloads.
- `DownloadStagingStore.adoptTemporaryFile(at: URL, taskID: UUID, attemptID: UUID) throws -> StagedFile` must preserve the file synchronously before the native completion delegate returns. Expensive validation/publication happens afterward.

- [ ] Write `BackgroundTransferTests.policyChangeDoesNotRewriteExistingTask`, `invalidResumeOffersRestart`, and `StagingRecoveryTests.callbackFileSurvivesDelegateReturn`. Assert `#expect(stagedFileExists)` after deleting the fixture's temporary callback location. Test old-attempt completion, system task missing from storage, progress with unknown total and delegate completion-handler draining.
- [ ] Run `swift test --package-path apple/Packages/SCTVKit --filter 'BackgroundTransferTests|StagingRecoveryTests'`; observe intended failures using an injected native driver, not a network-dependent unit test.
- [ ] Implement a bounded session set with fixed identifiers for allow/disallow-cellular policy, durable correlation and resume references. Resuming may replace the native task ID within the same attempt; check both current correlation and attempt so cancellation callbacks from the pre-pause native task cannot cancel its resumed replacement. Native callbacks enter the guarded coordinator; a missing resume capability yields restart rather than a false paused/resumable state. Keep metadata headers out of transfer requests; use validated media headers and document system-managed redirects.
- [ ] Wire iOS background-event completion and Mac delegate lifecycle separately. Recreate sessions on launch and reconcile before reporting task status. Adopt temporary files before returning from the delegate, then persist the staged reference. Recover interrupted adoption/commit windows by task/attempt staging identity, never by filename alone.
- [ ] Run unit suites and real background transfers against controlled fixture media on iPhone/iPad and Mac. Exercise suspension, lock, system termination where reproducible, explicit force-quit/relaunch, and Mac window close/application quit separately. Mark device-only scenarios unavailable if no device is accessible; do not equate driver mocks with OS verification. Review boundary: `feat(apple): integrate background transfer lifecycle` (commit only if authorized).

## Task C3: File publication, download UI and local playback

**Files:**

- Create: `Sources/SCTVCore/Downloads/DownloadedFileAccess.swift`; consume the destination/file values defined in C1.
- Create: `Sources/SCTVDownloads/Files/{FilePublisher.swift,FileAvailability.swift,FileExportService.swift,SecurityScopedDirectory.swift}`.
- Create: `Sources/SCTVFeatures/Downloads/{DownloadsView.swift,DownloadsModel.swift,DownloadRow.swift,DownloadActions.swift}`, `apple/Apps/macOS/DownloadDirectoryPicker.swift`.
- Test: `Tests/SCTVDownloadsTests/{FilePublicationTests.swift,FileActionTests.swift}`, `Tests/SCTVFeaturesTests/DownloadsModelTests.swift`, `apple/UITests/{iOS,macOS}/DownloadFlowTests.swift`.
- Modify: archive batch/single download actions, settings storage actions, playback local source handling and composition.

**Interfaces:**

- `FileDestination` distinguishes application-managed and authorized-external locations; persisted bookmarks stay in native storage rather than shared preferences.
- `FilePublisher.publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile` returns a durable relative/bookmark-backed reference, actual size and file identity.
- `DownloadedFileAccess.open(_ taskID: UUID) async throws -> LocalFileLease`; `LocalFileLease` owns URL and balanced release of security-scoped access for the whole player/share lifetime.
- `@MainActor DownloadsModel` consumes DownloadService; `selectFilter(_ filter: DownloadFilter)`, `setSelection(_ ids: Set<UUID>)`, `perform(_ action: DownloadAction) async`. Applicability is derived from task state and current attempt.

- [ ] Write `FilePublicationTests.revokedBookmarkRetainsStagedBytes`, `diskFullIsRetryable`, `sameNameNeverOverwritesUnrelatedFile`, and `FileActionTests.recordRemovalPreservesFile`. Assert `#expect(stagedFileExists)` after failed publication and `#expect(fileExists)` after record removal. Verify deleting the file keeps a missing-file record and never opens an online replacement.
- [ ] Run `swift test --package-path apple/Packages/SCTVKit --filter 'FilePublicationTests|FileActionTests|DownloadsModelTests'` and observe failures before adding publication/UI behavior.
- [ ] Implement safe destination names using shared download-name fixtures, collision-safe publication and recovery pointers retained until cleanup completes. iOS uses `Documents/Downloads` with Files visibility and backup exclusion; Mac defaults to application-owned storage and supports explicit external authorization. Export cancellation leaves local media intact. Security-scoped access spans external playback/export and always has a release path.
- [ ] Replace the development placeholder with native download lists and capability-aware row/batch actions. Filters retain their own position; changing filter clears selection. Archive preparation reports per-file fallbacks/failures without forcing navigation. Tests cover mixed-success batches, unavailable resume, publication retry and action confirmation against a replaced attempt.
- [ ] Run suites and all three UI checks for online download to completed file to offline playback. Verify Finder/Files/export actions, keyboard selection, large text, and expired directory access. Review boundary: `feat(apple): add native download management and offline playback` (commit only if authorized).

## Task C4: Reproducible checks, platform acceptance and documentation

**Files:**

- Create: `.github/workflows/apple.yml`, `docs/apple.md` and `apple/UITests/{iOS,macOS}/ApplicationAcceptanceTests.swift`.
- Modify: `apple/tool/check.mjs`, `apple/tool/check.test.mjs`, `apple/README.md`, `apple/AGENTS.md`, `README.md`, `docs/maintenance.md`, `.github/dependabot.yml`, `.gitignore`, `.prettierignore` and root docs-check globs as needed.
- Remove after acceptance and link migration: this plan family and its superseded specification.

**Interfaces:**

- The documented `check.mjs` commands from the index remain stable. Add `--configuration Release` for unsigned compilation and `--verify-lockfiles` to reject dependency resolution changes; these are CLI contracts tested in `check.test.mjs`.
- CI runs only relevant Apple/shared-fixture/tooling changes with read-only permissions, bounded timeouts, concurrency cancellation and result artifacts. Do not add signing secrets or automatic release publishing.

- [ ] Add `ApplicationAcceptanceTests` for VoiceOver labels/focus order, large text, reduced motion/transparency, window/rotation continuity, and recoverable loading/empty/error states. In `check.test.mjs`, assert missing OS 26 and changed lockfiles produce nonzero exit, and disposable-device cleanup runs after subprocess failure. Observe those new assertions failing before extending tooling.
- [ ] Implement locked dependency resolution, Swift format checking, package tests, native UI tests and unsigned release builds in the checker/workflow. Select and document an available CI Xcode/runner that satisfies the deployment baseline; verify availability at implementation time, not by copying the local Xcode 27.1 observation. Add Swift dependency-update configuration for actual checked-in manifests/lockfiles.
- [ ] Run `node --test apple/tool/check.test.mjs`, all three platform checks, Swift formatting, unsigned release builds, `pnpm format:check`, `pnpm docs:check`, and `pnpm ci:lint`. Run `pnpm check` and `pnpm build` if root runtime/tooling configuration changed since A1. Inspect uploaded/local result bundles and screenshots. A workflow file passing lint does not establish a successful hosted workflow run.
- [ ] Complete the physical-device matrix for OS 26 and a current OS where available: background/PiP/audio interruption, force-quit/relaunch, low disk space, missing files, bookmark renewal, and backup-exclusion behavior. Separate actual backup/restore evidence from file-attribute inspection. Keep any unavailable acceptance item explicit; do not mark the release ready while required rows are missing.
- [ ] Move verified contracts and commands into durable documentation, update README to describe the actually available client, and remove obsolete plans/spec only after their requirements are met. Review all diffs for unrelated client changes. Suggested final boundary: `ci(apple): add native validation and architecture docs` (commit only if authorized). Signed install/TestFlight/App Store/notarization work is a separate authorized delivery task.

## Exit artifact

An implemented client with passing automated checks and an honest platform/device acceptance report. If physical-device access or external CI execution is unavailable, deliver the implementation and exact remaining gates without claiming complete release acceptance.
