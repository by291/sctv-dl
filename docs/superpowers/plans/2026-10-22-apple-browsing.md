# Apple Browsing and Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver usable programme browsing, native navigation, settings, favourites and durable playback history on all three platforms.

**Architecture:** SQLite repositories implement core ports. Main-actor page models consume immutable snapshots; platform roots own navigation and inject the existing media presentation.

**Tech Stack:** SwiftUI/Observation, URLSession, GRDB, Nuke/NukeUI, Swift Testing and XCTest.

**Spec:** [Approved design](../specs/2026-10-22-apple-client-design.md); [plan index](2026-10-22-apple-client.md). Prerequisite: [phase A](2026-10-22-apple-media.md).

## Global Constraints

Inherit every constraint and verification convention in the index. Metadata bodies are limited to 2 MiB. History retains the newest 500 entries, writes advancing progress at five-second intervals and uses the 95% completion boundary. Documentation is English; product copy is Chinese. Preserve live navigation and accepted snapshots across refresh and appearance changes.

## Review Focus

Numeric ID precision and timezone boundaries belong to B1. Late responses after route changes belong to B2. Restored navigation to removed dates belongs to B3. Removed history reappearing through an old session and appearance changes interrupting PiP belong to B4.

## Task B1: Validated metadata transport and durable storage

**Files:**

- Create: `Sources/SCTVCore/Programmes/{ProgrammeAPI.swift,ProgrammeRules.swift}`, `Sources/SCTVCore/Preferences/Preferences.swift`.
- Create: `Sources/SCTVData/Network/{ProgrammeHTTPClient.swift,BoundedHTTPBody.swift,GuestRequestProfile.swift,InstallationIdentity.swift,ProgrammeDecoder.swift}`.
- Create: `Sources/SCTVData/Storage/{DatabaseFactory.swift,UserMigrations.swift,RuntimeMigrations.swift,StorageLocations.swift}`.
- Test: `Tests/SCTVDataTests/{ProgrammeHTTPTests.swift,ProgrammeDecoderTests.swift,DatabaseMigrationTests.swift}` and `Tests/SCTVCoreTests/ProgrammeRulesTests.swift`.
- Modify: package declarations to add SCTVData and a stable compatible GRDB release, plus the package/application resolved lockfiles produced by their actual resolution workflows.

**Interfaces:**

- `ProgrammeAPI: Sendable`: `catalogue() async throws -> [Programme]`, `dates(programmeID: String) async throws -> [BroadcastDate]`, `contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent]`.
- `ProgrammeDecoder.decodeContents(_ data: Data) throws -> [ProgrammeContent]`; corresponding catalogue/date decoders validate the HTTP envelope before record decoding.
- `ProgrammeRules.isFullEpisode(title: String, programmeName: String, broadcastDate: String) -> Bool`; `sortClips(_ contents: [ProgrammeContent], ascending: Bool) -> [ProgrammeContent]`.
- `DatabaseFactory.open(at locations: StorageLocations) throws -> DatabaseStores` returns separate user/runtime GRDB writers; only SCTVData exposes these concrete handles.
- `Preferences: Codable, Equatable, Sendable`: appearance (system/light/dark), playback quality and allow-cellular-downloads; defaults follow shared settings where applicable, with cellular downloads disabled initially.

- [ ] Write `ProgrammeHTTPTests.boundsChunkedMetadataBeforeBuffering` with `#expect(receivedAcceptedBytes <= 2 * 1024 * 1024)` and rejection on the next byte. Test redirects, HTTP/business errors, cancelled reads, header/body deadlines, and guest headers appearing only on metadata. Write shared-fixture decoder/rule tests including numeric `9007199254740992` rejection, the same string ID acceptance, BOM versus next-line trimming, newest-first date deduplication, and Asia/Shanghai publication-time interpretation.
- [ ] Run `swift test --package-path apple/Packages/SCTVKit --filter 'ProgrammeHTTPTests|ProgrammeDecoderTests|ProgrammeRulesTests|DatabaseMigrationTests'`; expect missing implementations or the named validation assertions to fail.
- [ ] Implement the API with a 20-second response-header deadline and a separate 20-second bounded metadata body deadline, each cancelled at its own lifecycle boundary. Do not apply metadata deadlines to media. Serialize installation UUID creation and exclude identity from backup. Use fixture-defined URL normalization and quality mapping, not Foundation defaults assumed equivalent to the existing contract.
- [ ] Implement versioned user/runtime database migrations and backup exclusions; create fixture tests that reopen an older schema and preserve favourites/history while recreating disposable cache. User database tables will be consumed by B2/B4, runtime download tables by C1. Keep network calls and file effects outside SQL transactions.
- [ ] Run the four suites with nonzero test counts, verify lockfiles contain stable releases and no absolute paths, then run the Mac and iOS build checks. Review boundary: `feat(apple): add validated programme data and storage` (commit only if authorized).

## Task B2: Accepted snapshots, favourites and settings

**Files:**

- Create: `Sources/SCTVCore/Programmes/{ProgrammeRepository.swift,ProgrammeSnapshot.swift}`, `Sources/SCTVCore/Preferences/{PreferenceRepository.swift,FavouriteRepository.swift}`.
- Create: `Sources/SCTVData/Programmes/{CachedProgrammeRepository.swift,SnapshotComparison.swift,BrowseStateRepository.swift}`, `Sources/SCTVData/Preferences/{SQLitePreferenceRepository.swift,SQLiteFavouriteRepository.swift}`.
- Test: `Tests/SCTVDataTests/{ProgrammeCacheTests.swift,PreferenceRepositoryTests.swift,FavouriteRepositoryTests.swift}`.

**Interfaces:**

- `ProgrammeQuery: Hashable, Sendable`: catalogue, dates(programmeID), contents(programmeID,dateID). `ProgrammeItems` uses matching typed array cases rather than untyped dictionaries.
- `ProgrammeSnapshot: Sendable` contains query, typed items, revision UUID and fetched timestamp. `ProgrammeUpdate: Sendable` contains accepted/pending snapshots and an optional typed warning; nil accepted means never fetched, not empty.
- `ProgrammeRepository: Sendable`: `observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate>`, `refresh(_ query: ProgrammeQuery) async throws`, `accept(_ query: ProgrammeQuery, revision: UUID) async throws`, `cancel(_ query: ProgrammeQuery) async`.
- `PreferenceRepository: Sendable`: `updates() async -> AsyncStream<PreferenceSnapshot>`, `save(_ preferences: Preferences, editRevision: UInt64) async throws`, `flush() async throws`; `PreferenceSnapshot` contains value, accepted revision, persisted flag and warning.
- `FavouriteRepository: Sendable`: `ids() async throws -> Set<String>`, `set(_ programmeID: String, isFavourite: Bool) async throws`, `updates() async -> AsyncStream<Set<String>>`.

- [ ] Write `ProgrammeCacheTests.lateResponseCannotReplaceNewGeneration`, `emptyIsFetched`, `unchangedFieldsKeepRevision`, and `acceptDatesBeforeContents`. Assert `#expect(accepted.items == newestRequestedItems)` after completing an older request last. Test refresh failure retaining accepted content, changed empty results waiting for acceptance, and selection blocking incompatible acceptance.
- [ ] Write `PreferenceRepositoryTests.delayedLoadCannotReplaceLocalEdit` and `FavouriteRepositoryTests.failedWritePreservesConfirmedState`; assert pending desired values remain retryable and `flush()` throws rather than claiming persistence. Run the three suites before implementation and observe the named failures.
- [ ] Implement keyed request cancellation, generation-guarded commits, normalized-field comparison and serialized cache writes. Every observation has termination cleanup. Browse state stores selected IDs, sort and stable scroll anchors with the snapshot revision; do not persist arbitrary SwiftUI values.
- [ ] Implement settings write serialization and revision guards; favourite presentation separates desired edits from confirmed storage. Exercise two repository observers to represent Mac windows and ensure one window's delayed hydration cannot overwrite the other's accepted update.
- [ ] Run `swift test --package-path apple/Packages/SCTVKit --filter 'ProgrammeCacheTests|PreferenceRepositoryTests|FavouriteRepositoryTests'`. Review boundary: `feat(apple): preserve accepted programme and preference state` (commit only if authorized).

## Task B3: Native shells, catalogue and archive

**Files:**

- Create: `Sources/SCTVFeatures/Catalogue/{CatalogueView.swift,CatalogueModel.swift,ProgrammeCard.swift}`, `Sources/SCTVFeatures/Archive/{ArchiveView.swift,ArchiveModel.swift,BroadcastDatePicker.swift,EpisodeSection.swift,ClipRow.swift}`.
- Create: `Sources/SCTVFeatures/Design/{ArtworkView.swift,LoadStateView.swift,PendingUpdateNotice.swift,PlayerPresentationFactory.swift}`.
- Create: `apple/Apps/iOS/{IOSRootView.swift,IOSNavigationModel.swift}`, `apple/Apps/macOS/{MacRootView.swift,MacNavigationModel.swift,AppCommands.swift}`, `apple/Apps/Shared/AppDependencies.swift`.
- Test: `Tests/SCTVFeaturesTests/{CatalogueModelTests.swift,ArchiveModelTests.swift}` and `apple/UITests/{iOS,macOS}/BrowseNavigationTests.swift`.
- Modify: application roots, Xcode project, package declarations/resolution for SCTVFeatures and stable Nuke/NukeUI, plus media presentation composition from A3.

**Interfaces:**

- `@MainActor CatalogueModel` consumes programme/favourite ports, exposes query/filter/sort and load state; actions `load() async`, `refresh() async`, `acceptUpdate() async`.
- `@MainActor ArchiveModel` consumes programme ports and pinned programme metadata; actions `selectDate(_ dateID: String) async`, `setSelection(_ ids: Set<String>)`, `acceptUpdate() async`, `play(_ contentID: String) async`.
- `@MainActor PlayerPresentationFactory` receives an active session UUID and returns the type-erased native player view supplied by application composition. It does not allocate an engine.
- Each window/root owns its navigation path and stable selection; `AppDependencies` owns repositories, media service and eventual downloads once per application.

- [ ] Write `ArchiveModelTests.removedRestoredDateSelectsNewestOnce` and `changingDateClearsIncompatibleSelection`, asserting exactly one request for the resolved date and no old-date selection. Write catalogue tests for empty search, favourites and stable sorting. Run `swift test --package-path apple/Packages/SCTVKit --filter 'CatalogueModelTests|ArchiveModelTests'` to observe failures.
- [ ] Implement catalogue/archive models and focused components. Date controls use existing available dates, not a calendar that implies unavailable broadcasts. Entire episodes keep service order; clips default ascending with unknown publication times last. Restore accepted date before requesting content. Pending-update controls preserve viewport and remain unavailable during incompatible batch selection.
- [ ] Implement the native shells and composition. iPhone tabs retain independent stacks; iPad compact/regular changes retain IDs; Mac windows retain independent navigation while sharing services. Add a dedicated artwork pipeline with redirect rejection, no guest headers, memory/disk limits and explicit cleanup. Use system controls/materials and blue semantic accents.
- [ ] Add UI tests for tab/back restoration, narrow iPad resize, Mac second-window independence, date presentation, searchable catalogue and keyboard focus. Use deterministic injected repositories and artwork; inspect light/dark, large text, loading/empty/error and pending-update screenshots. Until C3, the Downloads destination is a clearly marked development placeholder and must not be reported as functional.
- [ ] Run model suites and all three platform checks with BrowseNavigationTests enabled. Review boundary: `feat(apple): add adaptive catalogue and archive navigation` (commit only if authorized).

## Task B4: Library, history, settings and player integration

**Files:**

- Create: `Sources/SCTVCore/History/{HistoryEntry.swift,HistoryRepository.swift,HistorySession.swift}`.
- Create: `Sources/SCTVData/History/{SQLiteHistoryRepository.swift,HistoryWriteGuard.swift}`, `Sources/SCTVMedia/Session/PlaybackHistoryRecorder.swift`.
- Create: `apple/Apps/Shared/PlaybackRequestResolver.swift` for composing programme/history ports into a prepared player request.
- Create: `Sources/SCTVFeatures/Library/{LibraryView.swift,LibraryModel.swift,HistoryView.swift,HistoryRow.swift}`, `Sources/SCTVFeatures/Settings/{SettingsView.swift,SettingsModel.swift}`.
- Test: `Tests/SCTVDataTests/HistoryRepositoryTests.swift`, `Tests/SCTVMediaTests/PlaybackHistoryTests.swift`, `apple/UITests/{iOS,macOS}/LibrarySettingsTests.swift`.
- Modify: player coordinator, app dependency composition and root/library/settings routes from A3/B3.

**Interfaces:**

- `HistoryEntry: Codable, Sendable` contains ContentRef, pinned programme/title/date/cover metadata, integer position milliseconds, nullable duration, viewing timestamp and completion.
- `HistoryRepository: Sendable`: `begin(_ request: PlaybackRequest) async throws -> HistorySession`, `record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) async throws`, `remove(_ content: ContentRef) async throws`, `clear() async throws`, `entries() async throws -> [HistoryEntry]`, `updates() async -> AsyncStream<[HistoryEntry]>`.
- `HistorySession: Sendable` contains UUID and optional previous entry. Repository-assigned timestamps order history. `PlaybackHistoryRecorder` consumes settled snapshots and an injected clock for deterministic five-second tests.
- `PlaybackRequestResolver.resolve(_ content: ContentRef, quality: VideoQuality) async throws -> PlaybackRequest` loads matching programme/date/content metadata and saved history through injected ports, resolves actual quality with A1's policy, and pins the resulting context. Retry refreshes sources for the same identity; it does not reuse an unrelated current archive selection.

- [ ] Write `HistoryRepositoryTests.clearInvalidatesOpenSessions`, `newerSessionWins`, `retainsNewest500`, and exact shared completion/resume fixture tests. Assert `#expect(entries.isEmpty)` after clear followed by an old write. Write `PlaybackHistoryTests.unsettledSeekDoesNotWriteZero` and `throttlesProgressButFlushesPause`; assert no periodic write at 4999 ms and one at 5000 ms using the injected clock.
- [ ] Run `swift test --package-path apple/Packages/SCTVKit --filter 'HistoryRepositoryTests|PlaybackHistoryTests'`; observe intended failures, then implement transactions, session/sequence guards and retryable persistence warnings. History failure must not turn working playback into a failed player.
- [ ] Connect playback preparation to pinned metadata, saved quality and history before opening a session. Fullscreen/PiP and ordinary player presentation share the same history token. Add continue-watching, favourite programmes and full history routes; opening a saved entry must not require a loaded catalogue. Completed content opens at zero, paused.
- [ ] Implement appearance/quality/network preferences and retry presentation with grouped settings. Mac adds the standard Settings scene and Command-comma; space affects only focused playback. UI tests change theme while playing/PiP, delete history while its session remains open, and return from settings without losing archive state. Cache cleanup preserves all user data and files.
- [ ] Run the two suites and all platform checks, inspecting state continuity and accessibility. Review boundary: `feat(apple): add library history and native settings` (commit only if authorized).

## Exit artifact

A usable online browsing/player client with native navigation and durable user state. Download functionality remains explicitly unfinished until [C](2026-10-22-apple-downloads.md); phase B success is not whole-client completion.
