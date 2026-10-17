# Android Feature Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Wait for the user's plan review and execution-method selection before implementation.

**Goal:** Complete Kotlin Android viewing history, resume, download management, pause/resume, storage maintenance, backup, player recovery, and presentation parity with the current Flutter client.

**Architecture:** Keep current module boundaries. Add a separately backed-up user database, evolve the runtime database non-destructively, and route downloads through legacy or Media3 adapters according to durable attempt ownership. Media3 owns transfer/cache execution; application service and JobScheduler adapters own permitted background execution and public-file publication.

**Tech Stack:** Kotlin, Compose Material 3, Navigation 3, Hilt, Room, DataStore, Coil, OkHttp, Media3 1.11.1, Android JobScheduler, JUnit, MockWebServer, Android instrumentation.

**Spec:** [Approved Android feature parity design](../specs/2026-10-17-android-feature-parity-design.md).

## Global Constraints

- Support Android 10 and newer (`minSdk = 29`); retain the existing API 37 compile/target configuration and pinned dependencies unless a demonstrated compatibility requirement changes it.
- Keep documentation, comments, tests, and future commit messages in English; product copy stays Chinese.
- Keep the existing `sctv-metadata.db` filename and its version-1 schema as an explicit migration source. Use forward Room migrations; never destructive migration.
- Preserve DataStore keys, application IDs, serialized route names, existing system download IDs, public files, and unrelated edits.
- Keep the newest 500 history entries. Complete at playback end or at least 95% of a known positive duration. Throttle advancing progress writes to once every five seconds, with event-triggered flushes.
- Open playback paused. Online and new local copies share a content identity. Legacy downloads without exact IDs use a separate task identity.
- Persist preparation before transfer submission. Paused, waiting, and finalizing tasks retain the active reservation. Unknown totals stay indeterminate.
- Preserve the existing meaning of Wi-Fi-only; do not substitute unmetered-network semantics. A new default applies only to future tasks.
- Keep accepted screen snapshots separate from newer repository state. Retain cancellation and stale-response rejection, media URL restrictions/Referer, and delayed player disposal.
- Exclude cached metadata, transfer indices/IDs, private media, installation identity, and public-video references from backup.
- Use a separate disposable agent-owned AVD, target its serial explicitly, and preserve the user's devices. Use fixture videos and stub servers; live media checks use HEAD or a small Range only.
- No commit, push, signing, or deployment is authorized. Checkpoints below are reviewed working-tree changes, not Git commits.

## Review Focus

- A restored user database must not resurrect a favourite removed before restore; import authority is exercised in Task 1.
- A delayed history save after clearing, route replacement, or reopening the same item must not restore a removed row or overwrite newer progress; Tasks 1 and 2 exercise this.
- A source changes its ETag, ignores Range, or returns a shorter object while resuming; Task 5 rejects mixed media and Task 6 preserves a truthful retry state.
- Wi-Fi-only and unrestricted tasks coexist during network loss, process death, and system execution limits; Task 5 proves both traffic isolation and recoverable state.
- A process dies after MediaStore insertion or file finalization but before the corresponding database write; Task 6 recovers the same publication without duplicates or false completion.

## Structure and Execution Decisions

The tasks are interdependent: shared accepted content identity connects history, player entry, downloads, and backup. Keep one integrated plan, with backend contracts established before their UI consumers.

Paths below are repository-relative. `core:domain` stays Android-free. New history UI lives under the existing `feature:programmes`; no new feature Gradle module is required. Concrete image-cache ownership stays with the `app` ImageLoader composition. The existing module-dependency check remains enabled.

Use the current checkout only after applying the execution skill's workspace-isolation procedure. Preserve the approved spec and this plan if execution moves to a worktree. Do not lose the untracked documents or implicitly commit them.

Native execution is recommended: the history and transfer contracts have several shared consumers, so one implementer can evolve them coherently, followed by independent whole-change review. Subagent-driven execution remains an available user choice.

### Background execution decision

Pinned Media3 1.11.1 `DownloadService` disables its legacy restart scheduler on API 31 and newer. Its network requirements are manager-wide, while this app persists policy per task. Do not assume that subclassing `DownloadService` plus `PlatformScheduler` satisfies the approved design.

Use Media3's `DownloadManager`, `DownloadIndex`, `ProgressiveDownloader`, and one non-evicting `SimpleCache` behind `ManagedTransferRuntime`. A small application foreground service handles explicit user starts; a `JobService` handles deferred recovery inside the job's own permitted lifetime. The job must not launch a background foreground service. Both obtain scoped runtime execution leases; transfers cannot run solely because the application singleton exists.

Schedule stable, persisted jobs for unrestricted transfers, Wi-Fi transfers, and local publication/cleanup. Wi-Fi jobs use `JobInfo.Builder.setRequiredNetwork()` with `TRANSPORT_WIFI`, without a network specifier or `NOT_METERED` requirement. The runtime also gates and binds each task's HTTP client to an eligible `Network`; never change the process-wide network or bypass an active VPN by binding its underlying physical interface. If a VPN's permitted network cannot be confirmed as Wi-Fi, wait with an accurate reason. Job/network loss cancels associated calls and returns affected attempts to waiting. User pause has priority over network/host availability. A local publication job requires no network.

Foreground service timeout and rejected starts stop or defer work truthfully. Use ordinary system scheduling/backoff; never repeatedly restart services to evade execution quotas. API 29 and API 37 fixtures must establish this behaviour before the feature is considered accepted.

---

### Task 1: Durable user data, exact content identity, and safe favourites import

**Files:**

- Create: `android/core/domain/src/main/kotlin/dev/sctvdl/domain/programme/ProgrammeSelection.kt`; `android/core/domain/src/main/kotlin/dev/sctvdl/domain/history/ViewingEntry.kt`; `android/core/domain/src/main/kotlin/dev/sctvdl/domain/repository/HistoryRepository.kt`.
- Create: `android/core/data/src/main/kotlin/dev/sctvdl/data/database/SctvUserDatabase.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/history/local/HistoryEntity.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/history/local/HistoryDao.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/history/RoomHistoryRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/database/LegacyUserImport.kt`.
- Modify: `android/core/data/src/main/kotlin/dev/sctvdl/data/favourites/RoomFavouriteRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/favourites/local/FavouriteDao.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/di/DatabaseModule.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/di/ProgrammesModule.kt`; `android/app/src/main/res/xml/backup_rules.xml`; `android/app/src/main/res/xml/data_extraction_rules.xml`.
- Test: `android/core/domain/src/test/kotlin/dev/sctvdl/domain/ViewingPolicyTest.kt`; `android/core/data/src/androidTest/kotlin/dev/sctvdl/data/history/UserDataTest.kt`. Export the new Room user schema under the existing schemas directory.

**Interfaces:**

- `ContentRef(programmeId: String, dateId: String, contentId: String)`; `ProgrammeSelection(programme: Programme, broadcast: BroadcastDate, content: ProgrammeContent)` exposes `ref: ContentRef`.
- `ViewingKey` has `Content(ref: ContentRef)` and `LegacyDownload(taskId: String)` variants. `ViewingTarget` has `Online(selection: ProgrammeSelection)` and `LegacyDownload(taskId: String, title: String, programmeName: String, broadcastDate: LocalDate)` variants and exposes its key.
- `ViewingEntry(target: ViewingTarget, positionMs: Long, durationMs: Long?, viewedAt: Instant, completed: Boolean)` exposes its key. `resumePositionMs(entry: ViewingEntry?): Long` returns zero for absent/completed entries.
- `HistoryRepository.observeEntries(): Flow<List<ViewingEntry>>`; `suspend begin(target: ViewingTarget): HistorySession`; `submit(session: HistorySession, entry: ViewingEntry): Deferred<HistoryWriteResult>`; `suspend remove(key: ViewingKey)`; `suspend clear()`.
- `HistorySession` contains its key, deletion generation, session generation, and `previous: ViewingEntry?`. `HistoryWriteResult` distinguishes `Saved` and `Invalidated`. Exceptions complete the returned Deferred exceptionally. Repository-owned supervised writes outlive a disposed ViewModel without retaining its UI/player.

- [ ] Write `ViewingPolicyTest` for unknown/zero duration, 94.9% versus 95%, completed replay, and distinct legacy/content keys; write `UserDataTest` for 501 entries, equal timestamps, interrupted import, restored authority, delayed saves after clear/remove, and an older session finishing after a newer session starts.

  ```kotlin
  assertEquals(0L, resumePositionMs(completedEntry))
  assertEquals(500, storedEntries.size)
  assertEquals(HistoryWriteResult.Invalidated, oldWrite.await())
  assertFalse(restoredFavouriteIds.contains(removedId))
  ```

- [ ] Run `./android/gradlew -p android :core:domain:test :core:data:compileDebugAndroidTestKotlin`; record the expected missing-contract failures. On the selected AVD, run `ANDROID_SERIAL="$SCTV_QA_SERIAL" ./android/gradlew -p android :core:data:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=dev.sctvdl.data.history.UserDataTest` once the test compiles and before completing the persistence behaviour.
- [ ] Implement `LegacyUserImport.ensureImported()` with a destination-user-database transaction containing both copied favourites and its completed marker. Block favourite reads/mutations until import completes; a restored completed marker wins over retained legacy rows. Preserve the old table and existing preference files.
- [ ] Implement `SctvUserDatabase` in `sctv-user.db`, the history repository, and pure history policy. Transactionally enforce deletion/session generations, completion, order, and the 500-entry bound. Serialize submitted writes. Add user database/journal entries to backup allowlists; keep runtime database excluded.
- [ ] Re-run the named tests; expect passing import, history, and generation assertions. Inspect Room schemas and backup rules, including an eligible user-only restore fixture; record eligibility separately from actual platform backup evidence.

### Task 2: Persist playback progress and expose viewing history

**Files:**

- Create: `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/PlaybackHistoryRecorder.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/history/HistoryRoute.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/history/HistoryViewModel.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/history/HistoryScreen.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/history/components/HistoryCard.kt`.
- Modify: `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/OnlinePlayerViewModel.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/local/LocalPlayerViewModel.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/PlayerUiState.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/PlaybackSelection.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/PlayerRoute.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/local/LocalPlayerRoute.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/PlayerScreen.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/components/PlaybackContent.kt`.
- Modify: `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/archive/ArchivePlaybackSelection.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/archive/ArchiveRoute.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/catalogue/CatalogueRoute.kt`; `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/catalogue/CatalogueScreen.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/navigation/AppRoute.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/navigation/AppDestinations.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/SctvApp.kt`.
- Modify: `android/core/player/src/main/kotlin/dev/sctvdl/player/model/PlaybackBackendSnapshot.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/model/PlaybackState.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/media3/PlayerSession.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/controller/PlaybackController.kt`.
- Test: `android/feature/player/src/test/kotlin/dev/sctvdl/feature/player/PlaybackHistoryRecorderTest.kt`; `android/feature/programmes/src/test/kotlin/dev/sctvdl/feature/programmes/history/HistoryViewModelTest.kt`; `android/feature/programmes/src/androidTest/kotlin/dev/sctvdl/feature/programmes/HistoryInteractionTest.kt`; `android/app/src/androidTest/kotlin/dev/sctvdl/app/HistoryPlaybackTest.kt`.

**Interfaces:** Consumes Task 1 history contracts. Add `ready`, `ended`, and `firstFrameRendered` Boolean state to backend/playback snapshots. `PlaybackHistoryRecorder.onProgress(state: PlaybackState)`, `onSeekCompleted(state: PlaybackState)`, `flush(state: PlaybackState)`, and `close(state: PlaybackState)` submit immutable snapshots through `HistoryRepository`; no player handle is stored. `HistoryRoute(onBack: () -> Unit, onOpen: (ViewingTarget) -> Unit)` is the cross-module UI entry. Add `AppRoute.History` without renaming current routes.

- [ ] Write recorder tests using an injected clock: saves at 0/5 seconds of advancing playback, no extra write at 4 seconds, immediate pause/seek/end/exit saves, and a failed save that does not disable playback. Assert invalidated sessions do not immediately retry their stale snapshot; a later actual viewing event can acquire a new session.
- [ ] Write history state/device tests for exact saved entry, completed versus incomplete startup, legacy local routing, local-day grouping, full titles, search/removal errors, search/scroll restoration, and back closing search. A two-colour fixture resumed after its colour boundary must reveal the resumed frame, not its opening frame.

  ```kotlin
  assertEquals(12_000L, openedSource.startPositionMs)
  assertFalse(openedPlayer.playWhenReady)
  assertEquals(expectedContentRef, openedSelection.ref)
  assertEquals(initialScrollOffset, restoredScrollOffset)
  ```

- [ ] Run `./android/gradlew -p android :feature:player:testDebugUnitTest :feature:programmes:testDebugUnitTest :app:compileDebugAndroidTestKotlin`; record the relevant red assertions/missing interfaces.
- [ ] Carry domain `ProgrammeSelection` through existing feature wrappers and app-held accepted selection. Preserve saved owner keys and live-entry position precedence. Resolve durable history with visible, nonfatal error feedback. Queue final snapshots before lifecycle disposal; keep the repository writer alive independently. Hold the accepted cover until native first-frame readiness at the requested position.
- [ ] Implement history destination, grouped/searchable cards, single-item removal, and toolbar entry. Retain independently owned list state. Preserve existing catalogue/favourite tabs, navigation transitions, PiP ownership, and delayed player release.
- [ ] Re-run unit tests and selected `HistoryInteractionTest`/`HistoryPlaybackTest` on the owned AVD; expect paused resume, correct pixels, durable exit progress, and unchanged underlying archive state.

### Task 3: Safe cache cleanup and history-clearing settings

**Files:**

- Create: `android/core/domain/src/main/kotlin/dev/sctvdl/domain/repository/StorageMaintenance.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/platform/AppStorageMaintenance.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/platform/CoverImageLoaderOwner.kt`; `android/core/ui/src/main/kotlin/dev/sctvdl/ui/media/LocalCoverImageLoader.kt`.
- Modify: `android/core/domain/src/main/kotlin/dev/sctvdl/domain/repository/ProgrammeRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/programmes/CachedProgrammeRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/programmes/local/SnapshotStore.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/programmes/local/RoomSnapshotStore.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/programmes/local/ProgrammeSnapshotDao.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/SctvApplication.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/SctvApp.kt`; `android/core/ui/src/main/kotlin/dev/sctvdl/ui/media/CoverImage.kt`.
- Modify: `android/feature/settings/src/main/kotlin/dev/sctvdl/feature/settings/SettingsViewModel.kt`; `android/feature/settings/src/main/kotlin/dev/sctvdl/feature/settings/SettingsRoute.kt`; `android/feature/settings/src/main/kotlin/dev/sctvdl/feature/settings/SettingsScreen.kt`; relevant fakes in `android/core/domain/src/testFixtures/kotlin/dev/sctvdl/domain/testing/FakeRepositories.kt`.
- Test: `android/core/data/src/test/kotlin/dev/sctvdl/data/programmes/CachedProgrammeRepositoryTest.kt`; `android/app/src/test/kotlin/dev/sctvdl/app/platform/AppStorageMaintenanceTest.kt`; `android/feature/settings/src/androidTest/kotlin/dev/sctvdl/feature/settings/StorageSettingsTest.kt`.

**Interfaces:** Add `ProgrammeRepository.clearCache(): Unit` and `SnapshotStore.clear(): Unit` as suspend functions. `StorageMaintenance.clearCache(): CacheCleanupResult` is suspend; `CacheCleanupResult(metadataCleared: Boolean, imagesCleared: Boolean, metadataFailure: AppError?, imageFailure: AppError?)` records both layers. `CoverImageLoaderOwner` exposes `loaders: StateFlow<ImageLoader>` and `suspend clearCache(): Unit`; `AppStorageMaintenance` composes it with `ProgrammeRepository`. The app provides the current loader through `LocalCoverImageLoader`, consumed by shared `CoverImage`; feature modules never import the owner. Settings consumes these contracts and Task 1 `HistoryRepository.clear()`.

- [ ] Add tests where an old refresh completes after clear and cannot repopulate storage; an old cover request cannot recreate the cleared cache; one cleanup layer fails while the other succeeds; downloads, history, favourites, and accepted displayed content remain available. Add confirmation/cancellation and retry UI tests.

  ```kotlin
  assertNull(snapshotStore.read("programmes"))
  assertEquals(beforeDownloads, downloadStore.all())
  assertEquals(beforeFavourites, favouriteIds)
  assertTrue(result.metadataCleared && result.imageFailure != null)
  ```

- [ ] Run the affected unit tests and compile `StorageSettingsTest`, confirming red behaviour before implementation.
- [ ] Add a cache epoch under the existing snapshot write lock; stale writes/errors cannot pass it. Clear only snapshot storage. For images, stop the old loader's requests before clearing its caches, rebuild through the existing factory, and atomically hand future requests to the replacement owner; share no stale writers with the new loader. Preserve image transport restrictions.
- [ ] Add separately confirmed cleanup/history actions with operation-specific busy/error state and accessible feedback. A partial result must name the failed layer instead of reporting full success.
- [ ] Run `./android/gradlew -p android :core:data:testDebugUnitTest :app:testDebugUnitTest :feature:settings:compileDebugAndroidTestKotlin`, then the selected storage settings device test; expect passing race and preservation assertions.

### Task 4: Evolve download records and action contracts without losing legacy jobs

**Files:**

- Create: `android/core/domain/src/main/kotlin/dev/sctvdl/domain/download/DownloadAction.kt`; `android/core/domain/src/main/kotlin/dev/sctvdl/domain/download/DownloadAttempt.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/database/RuntimeMigrations.kt`.
- Modify: `android/core/domain/src/main/kotlin/dev/sctvdl/domain/download/DownloadRequest.kt`; `android/core/domain/src/main/kotlin/dev/sctvdl/domain/download/DownloadTask.kt`; `android/core/domain/src/main/kotlin/dev/sctvdl/domain/download/DownloadState.kt`; `android/core/domain/src/main/kotlin/dev/sctvdl/domain/repository/DownloadRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/local/DownloadEntity.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/local/DownloadDao.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/local/DownloadStore.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/local/RoomDownloadStore.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/database/SctvDatabase.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/di/DatabaseModule.kt`.
- Modify all request builders in `android/feature/programmes/src/main/kotlin/dev/sctvdl/feature/programmes/archive/ArchiveViewModel.kt`, `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/PlayerScreen.kt`, and affected test fixtures.
- Test: `android/core/domain/src/test/kotlin/dev/sctvdl/domain/DownloadActionsTest.kt`; `android/core/data/src/androidTest/kotlin/dev/sctvdl/data/downloads/DownloadMigrationTest.kt`. Add exported runtime schema version 2; preserve version 1 byte-for-byte.

**Interfaces:** Keep existing methods callable during migration. Add `DownloadOwner { LegacySystem, Media3 }`, `DownloadTarget(id: String, attemptId: String)`, `DownloadAction { Pause, Resume, Retry, Publish, Cancel, DeleteFile, RemoveRecord }`, and sealed `DownloadActionResult` with `Applied`, `Skipped`, and `ConsentRequired(token: String)`. Add suspend `DownloadRepository.perform(target: DownloadTarget, action: DownloadAction): DownloadActionResult` and `completeFileConsent(target: DownloadTarget, token: String, granted: Boolean): DownloadActionResult`. Domain `supportedActions(task: DownloadTask): Set<DownloadAction>` is shared by UI/repository. `DownloadRequest` retains current fields and gains `selection: ProgrammeSelection? = null` for legacy compatibility; new app requests supply it.

- [ ] Add migration fixtures containing every old state, an ambiguous reservation, a completed URI, and an active system ID. Assert preserved fields, no enqueue on migration, legacy owner defaults, and paused/finalizing uniqueness. Assert unsupported actions and changed attempt IDs are skipped.

  ```kotlin
  assertEquals(oldSystemId, migrated.systemId)
  assertEquals(DownloadOwner.LegacySystem, migrated.owner)
  assertEquals(migrated.id, migrated.attemptId)
  assertFalse(DownloadAction.Pause in supportedActions(migrated))
  ```

- [ ] Run `./android/gradlew -p android :core:domain:test :core:data:compileDebugAndroidTestKotlin` and observe red contract/migration results.
- [ ] Migrate runtime version 1 to 2, adding owner, attempt ID, revision, accepted selection, private cache identity, publication URI, publication/cleanup bookkeeping, resumability metadata, and user-pause fields with explicit legacy defaults. Backfill attempt IDs from task IDs in SQL. Keep old serialized state names and stable reservation keys; new content-aware matching must also check unresolved legacy content/quality reservations.
- [ ] Add atomic attempt/state validation under the existing repository transition boundary. Adapt legacy methods and fakes without advertising unsupported pause/resume. Persist accepted artwork/IDs in new submissions, and use Task 1 history identity for new local playback.
- [ ] Run domain tests and selected `DownloadMigrationTest`; expect schema validation and all legacy invariants to pass before installing the new engine.

### Task 5: Managed Media3 transfers, resumability, and execution ownership

**Files:**

- Create under `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/managed/`: `ManagedTransferGateway.kt`, `Media3TransferGateway.kt`, `ManagedTransferRuntime.kt`, `ManagedDownloadService.kt`, `ManagedDownloadJobService.kt`, `DownloadRecoveryScheduler.kt`, `DownloadNetworkPolicy.kt`, `NetworkBoundMediaSource.kt`, `ResumeValidator.kt`, and `ManagedDownloadNotifications.kt`.
- Modify: `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/preflight/MediaPreflight.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/preflight/OkHttpMediaProbe.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/di/DownloadsModule.kt`; `android/core/data/build.gradle.kts`; `android/gradle/libs.versions.toml`; `android/core/data/src/main/AndroidManifest.xml`; `android/app/src/main/AndroidManifest.xml`; `android/app/src/main/kotlin/dev/sctvdl/app/MainActivity.kt`.
- Test: `android/core/data/src/test/kotlin/dev/sctvdl/data/downloads/managed/DownloadNetworkPolicyTest.kt`; `android/core/data/src/test/kotlin/dev/sctvdl/data/downloads/managed/ResumeValidatorTest.kt`; `android/core/data/src/androidTest/kotlin/dev/sctvdl/data/downloads/managed/ManagedTransferTest.kt`; `android/core/data/src/androidTest/kotlin/dev/sctvdl/data/downloads/managed/DownloadExecutionTest.kt`.

**Interfaces:** `ManagedTransferGateway` exposes `suspend enqueue(task: DownloadTask)`, `suspend pause(attemptId: String)`, `suspend resume(attemptId: String)`, `suspend remove(attemptId: String)`, `suspend snapshots(): List<ManagedTransferSnapshot>`, `updates: Flow<ManagedTransferSnapshot>`, and `suspend shutdown()`. A snapshot contains attempt ID, transfer phase, bytes/optional total, private cache key, resumability, and typed failure. Add `suspend MediaPreflight.inspect(url: String): MediaIdentity`, retaining `check(url): Long?` for legacy callers; identity contains total length, strong ETag/Last-Modified when returned, and observed range support. `ManagedTransferRuntime.acquire(owner: ExecutionOwner): ExecutionLease`; closing the lease withdraws that host's permission to run. Owners identify foreground execution, a policy-specific JobService job, or local publication. `DownloadRecoveryScheduler.reconcile()` schedules/cancels the three stable job categories from durable unfinished work.

- [ ] Add tests for user pause surviving manager reconstruction; same-validator ranged continuation; changed/missing validators; ignored Range/invalid Content-Range; unknown lengths; cancel/retry cleanup; stale listener events; and bootstrap remaining stopped until an execution lease exists. Verify final fixture bytes, not just transferred counters.
- [ ] Add mixed-policy tests: Wi-Fi blocked on Ethernet/cellular, metered Wi-Fi allowed, unrestricted work continuing while Wi-Fi waits, cancellation at network loss, no VPN bypass, and no fallback of a Wi-Fi socket onto the default cellular network. Test screen-off transfer, job stop, notification denial, service start rejection, and timeout without an automatic foreground restart loop.

  ```kotlin
  assertEquals(0, disallowedNetworkRequests)
  assertContentEquals(originalFixtureBytes, completedBytes)
  assertEquals(pausedBytes, restoredPausedBytes)
  assertFalse(runtimeHasExecutionLeaseAfterJobStop)
  ```

- [ ] Run managed unit tests and compile the device tests; capture red assertions before implementing their respective paths.
- [ ] Implement the gateway using pinned Media3 progressive downloading and a single non-evicting cache/index owner. Add existing-version Media3 artifacts to the catalogue as needed. Persist task-specific pause with stop reasons; recompute transient network/host reasons on restart. Validate resource identity and every ranged response before writing bytes into an existing cache key. A server that cannot establish safe continuation must produce a truthful restart-required outcome rather than mixed cached bytes.
- [ ] Implement the execution design above with application service/JobService adapters, per-network OkHttp clients/DNS, task-policy gates, bounded scheduling/backoff, and lease cleanup. The foreground host holds a partial wake lock only while transfer/publication work is executing and releases it on idle, pause, timeout, or destruction; JobService execution uses its system-managed lifetime. Declare `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, and persisted-job boot permission where applicable. Request notification permission from the Activity, keeping refusal nonfatal. Preserve one-shot download navigation.
- [ ] Run `./android/gradlew -p android :core:data:testDebugUnitTest :core:data:compileDebugAndroidTestKotlin`; run selected `ManagedTransferTest` and `DownloadExecutionTest` on API 29 and API 37. Use small controlled files and actual process recreation/restart evidence; distinguish normal reclamation from force-stop. Do not proceed to completion claims while network-bound traffic or modern background ownership remains unverified.

### Task 6: Public-file publication and one durable repository over both engines

**Files:**

- Create: `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/ManagedDownloadRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/DownloadPublication.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/platform/PublicDownloadFiles.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/platform/MediaStoreDownloadFiles.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/di/DownloadFileConsentRegistry.kt`.
- Modify: `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/DownloadManagerRepository.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/DownloadReconciler.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/platform/DownloadManagerGateway.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/downloads/platform/DownloadEventsReceiver.kt`; `android/core/data/src/main/kotlin/dev/sctvdl/data/di/DownloadsModule.kt`; Task 5 runtime and recovery scheduler.
- Test: `android/core/data/src/test/kotlin/dev/sctvdl/data/downloads/ManagedDownloadRepositoryTest.kt`; existing legacy repository/reconciler tests; `android/core/data/src/androidTest/kotlin/dev/sctvdl/data/downloads/DownloadPublicationTest.kt`; `android/core/data/src/androidTest/kotlin/dev/sctvdl/data/downloads/DownloadStorageTest.kt`.

**Interfaces:** `PublicDownloadFiles` provides suspend `reserve(task: DownloadTask): String`, `copyCached(task: DownloadTask, pendingUri: String): Long`, `finalize(pendingUri: String): Unit`, `isReadable(uri: String): Boolean`, `delete(uri: String): FileDeleteResult`, and `findPlanned(task: DownloadTask): List<String>`. `FileDeleteResult` distinguishes deleted, missing, and a typed Android consent request retained by `DownloadFileConsentRegistry`. This small public platform integration contract exposes `intentSender(token: String): IntentSender?` to the app; features receive only Task 4's opaque token. Bind tokens to attempt/URI and consume them once in `completeFileConsent`; expired tokens are skipped. `DownloadPublication.publish(target: DownloadTarget)` is suspend. `ManagedDownloadRepository` implements the Task 4 repository contract and delegates legacy operations according to persisted owner.

- [ ] Add failure-injection tests at MediaStore row insertion, URI persistence, mid-copy, finalization, completion persistence, and private-cache cleanup. Assert one visible file, readable complete bytes, retry without network, no lost private media on failure, and no automatic adoption of ambiguous candidates.
- [ ] Add upgrade coexistence, duplicate reservation, stale completion after retry, preflight cancellation, publication/delete races, missing-file detection, consent cancellation, terminal-record removal, and partial-batch submission tests.

  ```kotlin
  assertEquals(1, publicFilesForAttempt.size)
  assertEquals(0, upstreamRequestsDuringPublicationRetry)
  assertTrue(publicFileSurvivesRecordRemoval)
  assertEquals(oldSystemId, untouchedLegacyTask.systemId)
  ```

- [ ] Run the new repository tests and existing `DownloadManagerRepositoryTest`/`DownloadReconcilerTest`, recording expected red results for the new orchestrator.
- [ ] Implement reservation/preflight/submission with distinct task and attempt identities. Start new work through Task 5; preserve legacy reconcile/cancel semantics and ambiguous-job safeguards. Explicit terminal retry moves to a managed attempt only after old ownership is resolved.
- [ ] Implement cache-only publication to `MediaStore.Downloads`, `RELATIVE_PATH=Downloads/sctv-dl`, with `IS_PENDING`. Journal the operation before insertion using the unique planned filename; persist the pending URI before copying. Recover the insertion-to-URI-write gap only from a unique application-owned planned match; never delete/adopt an ambiguous or unowned row. Finalize then confirm readability, persist completion, and retry private-resource cleanup separately.
- [ ] Implement file deletion that retains the record, terminal record removal that retains public media, and cancellation that removes only the current attempt's partial resources. Route recoverable platform consent to the Activity; revalidate identity after its result. Publication uses the local execution job even when offline.
- [ ] Re-run repository and storage/publication device tests. Reopen databases/cache/services at each crash boundary and exercise a host-driven process-death fixture. Expect unchanged legacy files/jobs and no duplicate publication.

### Task 7: Download filters, batch actions, and complete task cards

**Files:**

- Create: `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/DownloadBatchActions.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/components/DownloadSelectionBar.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/platform/DownloadFileConsentHost.kt`.
- Modify: `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/DownloadsUiState.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/DownloadsViewModel.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/DownloadsRoute.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/DownloadsScreen.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/DownloadPresentation.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/components/DownloadCard.kt`; `android/feature/downloads/src/main/kotlin/dev/sctvdl/feature/downloads/platform/DownloadFileActions.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/navigation/AppDestinations.kt`; `android/app/src/main/kotlin/dev/sctvdl/app/SctvApp.kt`.
- Test: existing `DownloadsViewModelTest.kt`; `android/feature/downloads/src/test/kotlin/dev/sctvdl/feature/downloads/DownloadBatchActionsTest.kt`; `android/feature/downloads/src/androidTest/kotlin/dev/sctvdl/feature/downloads/DownloadManagementTest.kt`.

**Interfaces:** `DownloadFilter { All, Active, Unfinished, Completed, Removed }` and `includes(task: DownloadTask): Boolean`; suspend `runDownloadBatch(repository: DownloadRepository, action: DownloadAction, targets: List<DownloadTarget>, requestConsent: suspend (String) -> Boolean): DownloadBatchOutcome`. Outcome contains applied IDs, skipped IDs, and per-ID failures. Repository `perform` remains the atomic authority; on `ConsentRequired`, the route-owned callback launches the app's `DownloadFileConsentHost`, then the batch calls `completeFileConsent`. Do not launch a system dialog from a ViewModel. Map old saved tab names to the corresponding new filters without changing the existing saved-state key.

- [ ] Add tests for all state/filter combinations, paused-active membership, publication failures, per-filter scroll retention, selection reset on filter change, destructive-action cancellation, stale attempts during confirmation, and a middle-item failure that does not stop the remaining batch.

  ```kotlin
  assertEquals(setOf("first", "third"), outcome.appliedIds)
  assertEquals(setOf("changed"), outcome.skippedIds)
  assertEquals(setOf("second"), outcome.failures.keys)
  assertTrue(selectionAfterFilterChange.isEmpty())
  ```

- [ ] Run `./android/gradlew -p android :feature:downloads:testDebugUnitTest` and capture red behaviour.
- [ ] Implement filter state, saved list positions, selection/back handling, select-all in the visible filter, and supported actions from domain policy. Confirm destructive scopes and surface applied/skipped/failure counts. Keep per-task operations guarded while platform consent is pending.
- [ ] Update cards with real accepted covers, complete programme/date/quality text, known completed size, neutral removed-file presentation, overflow file actions, and wrapping labelled primary actions. Keep loading, observation failure/retry, empty/filter-empty, and partial-action failure reachable. Preserve truthful legacy capability feedback and system-download access.
- [ ] Re-run unit tests and selected `DownloadManagementTest`; inspect light/dark, narrow/wide, 200% text, keyboard focus, and back from batch mode. Expect no stale-target mutation or fabricated transfer information.

### Task 8: Recover failed quality switches without unintended autoplay

**Files:**

- Modify: `android/core/player/src/main/kotlin/dev/sctvdl/player/controller/PlaybackController.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/controller/PlaybackBackend.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/model/PlaybackState.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/media3/PlayerSession.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/ui/PlayerVideo.kt`.
- Test: `android/core/player/src/test/kotlin/dev/sctvdl/player/controller/PlaybackControllerTest.kt`; `android/core/player/src/androidTest/kotlin/dev/sctvdl/player/media3/PlayerSessionTest.kt`.

**Interfaces:** Consume Task 2 readiness/first-frame signals. Preserve existing controller methods. Add explicit switching/recovering phase and nonfatal notice to `PlaybackState`. Route UI play/pause and seek through controller actions so play-intent generations are observable. Backend reports externally caused pauses/audio-focus events separately from source-replacement preparation where required.

- [ ] Add tests for asynchronous target failure after position 12 seconds at 1.5×, successful rollback, rollback failure with retained retry context, old callbacks, and a user pause/background/exit while switch or rollback is pending. Assert no quality commit before readiness and no retry loop.

  ```kotlin
  assertEquals(previousQuality, recovered.quality)
  assertEquals(12_000L, restoredPositionMs)
  assertEquals(1.5f, restoredSpeed)
  assertFalse(playWhenReadyAfterInterveningPause)
  ```

- [ ] Run `./android/gradlew -p android :core:player:testDebugUnitTest`; verify failures reproduce absent rollback/intent handling.
- [ ] Implement a typed switch operation with prior usable source/context and an operation token. Commit new quality after ready; perform at most one rollback. Keep play intent independent of decoder's transient state and reject stale source callbacks. Preserve source/position/speed for explicit retry when restoration also fails.
- [ ] Re-run controller tests and native `PlayerSessionTest` with a failing replacement fixture; expect one live player/session and correct pause/background semantics.

### Task 9: Compact accessible player controls and resume presentation

**Files:**

- Modify: `android/core/player/src/main/kotlin/dev/sctvdl/player/ui/PlayerControls.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/ui/PlayerProgressSlider.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/ui/PlayerChoiceMenu.kt`; `android/core/player/src/main/kotlin/dev/sctvdl/player/ui/PlayerVideo.kt`; `android/feature/player/src/main/kotlin/dev/sctvdl/feature/player/components/PlaybackContent.kt`.
- Test: `android/feature/player/src/androidTest/kotlin/dev/sctvdl/feature/player/PlayerOverlayTest.kt`; `android/feature/player/src/androidTest/kotlin/dev/sctvdl/feature/player/PlayerWindowTest.kt`; `android/feature/player/src/androidTest/kotlin/dev/sctvdl/feature/player/PlayerControlsAccessibilityTest.kt`.

**Interfaces:** Reuse controller actions from Task 8. Add no new feature dependency. Any timestamp formatter remains a small pure presentation helper beside the player controls, with hour-aware values and unknown duration preserved.

- [ ] Add observable control tests for 59:59 to 1:00:00 without moving the seek/button anchors, single-quality inspection without reloading, menu/back/focus holds, narrow 200% text reachability, and a 3.5-second playing-only hide timeout. Test resumed cover removal only after the correct first frame.
- [ ] Run `./android/gradlew -p android :feature:player:compileDebugAndroidTestKotlin`, then the selected new control tests before finishing layout changes; retain screenshots of failing geometry/visibility cases where applicable.
- [ ] Build one compact bottom row with stable time/label widths and horizontal overflow when needed. Keep 48 dp targets, tabular digits, PiP at the upper right, upward bounded menus, and no unnecessary chevrons. Replace direct Media3 button mutations with controller-owned actions while preserving native accessibility semantics and ended-video replay.
- [ ] Run player overlay/window/accessibility tests and inspect both themes, wide/narrow windows, text scaling, fullscreen, PiP, reduced motion, and keyboard focus. Confirm the same session and surrounding scroll state survive layout changes.

### Task 10: Full regression, upgrade evidence, documentation, and handoff

**Files:** Modify `android/README.md`, `android/AGENTS.md`, and `docs/android-client-design.md` to describe implemented contracts. Add `docs/android-feature-parity-validation.md` for actual evidence and limitations. Update only affected existing test fixtures or baseline journeys if their behaviour changed. Remove the obsolete parity plan/spec after their durable constraints and acceptance evidence have been incorporated.

**Interfaces:** All tasks above. No new product functionality is introduced during final verification.

- [ ] Run `./android/gradlew -p android spotlessApply`, inspect the diff for unrelated formatter changes, then run `./android/gradlew -p android spotlessCheck check :app:assembleDebug :app:assembleRelease :app:assembleDebugAndroidTest`. Require `BUILD SUCCESSFUL` with no unresolved test/lint/module-boundary failure; fix failures at their owning task.
- [ ] On explicitly selected disposable API 29/API 37 runtimes, run relevant module and app instrumentation using `ANDROID_SERIAL="$SCTV_QA_SERIAL" ./android/gradlew -p android connectedDebugAndroidTest`. If the known API 37 Espresso incompatibility remains, run compatible UI Automator/non-Espresso coverage there and the Compose suite on API 29; report the limitation rather than silently dropping tests.
- [ ] Validate upgrade from a version-1 fixture with favourites, an active legacy transfer, and an existing completed file. Validate user-only restore to a clean runtime, including online history and missing local-media handling. Test backup eligibility separately from an actual system backup/restore attempt.
- [ ] Exercise the integrated history-to-paused-resume journey, online/local shared progress, legacy local resume, managed pause/process-restart/resume, network policy, retry/publication failures, batch stale selection, file deletion, cache clearing during refresh, quality rollback, notification return, fullscreen/PiP, and predictive-back cancellation/commit. Use controlled files and inspect resulting bytes/URIs, not only UI labels.
- [ ] Update permanent documentation and `android/AGENTS.md`: replace the old universal no-pause rule with legacy/managed capabilities; document the new user/runtime database split, publication ownership, settings, restore scope, service/job limitations, and exact checks. Do not copy implementation checklists into permanent docs.
- [ ] Run `pnpm format:check`, local documentation-link checks, and `git diff --check`. Run `pnpm check` and `pnpm build` only if shared Web/tooling behaviour changed. Review the whole diff, perform the execution method's independent review, and resolve its actionable findings with focused regressions.
- [ ] Restore temporary device/network/display settings and verify reported display values plus a screenshot. Stop only owned fixtures/emulators and preserve evidence outside tracked generated paths. Report implemented scope, actual unit/build/device/backup evidence, remaining limitations, and the uncommitted working-tree status.

## Plan Self-Review

- Every approved feature is assigned: history/backup (1–2), cleanup (3), compatible download state (4), pause/background/network (5), publication/file deletion (6), batch/card presentation (7), quality recovery (8), controls (9), and integration evidence/docs (10).
- Shared identity and history interfaces are defined before their consumers. Download UI uses Task 4 actions, Task 5 owns transfers, and Task 6 owns publication and repository coordination.
- All five review-focus conditions have named tests. Legacy system tasks are never assigned unsupported capabilities, and current Android execution limits are not delegated to an unavailable Media3 restart scheduler.
- No product implementation, dependency installation, commit, or device mutation has been performed during planning.

## Platform References

- [Media3 download APIs](https://developer.android.com/media/media3/exoplayer/downloading-media).
- [JobInfo.Builder network requirements and persisted scheduling](https://developer.android.com/reference/android/app/job/JobInfo.Builder).
- [Foreground service time limits](https://developer.android.com/develop/background-work/services/fgs/timeout).
- Media3 1.11.1 and Android API 37 source artifacts were inspected locally for the scheduler, progressive downloader, and NetworkRequest constraints.
