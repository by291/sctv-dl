# Apple Media and Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish buildable native hosts and prove supported MP4 playback before developing the full application.

**Architecture:** A minimal core package defines typed media inputs. A controlled range transport feeds an AVAssetResourceLoader-backed player; platform wrappers own presentation only.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation/AVKit, URLSession, Swift Testing, XCTest and Node-only test tooling.

**Spec:** [Approved design](../specs/2026-10-22-apple-client-design.md); [plan index](2026-10-22-apple-client.md).

## Global Constraints

Inherit every constraint and verification convention in the plan index. Minimum systems are iOS 26, iPadOS 26 and macOS 26. Opening content starts paused. No unsupported AVURLAsset header option or full-episode buffering. This phase adds no production GRDB/Nuke dependency until its consumer is implemented.

## Review Focus

Range mismatches and truncated bodies belong to A2; cancelled quality replacement, interactive dismissal and PiP ownership belong to A3. Production transport must retain its host allowlist even when tests use localhost.

## Task A1: Buildable hosts and core media policies

**Files:**

- Create: `apple/SCTV.xcodeproj/project.pbxproj`, `apple/SCTV.xcodeproj/xcshareddata/xcschemes/{SCTViOS,SCTVmacOS}.xcscheme`, `apple/Packages/SCTVKit/Package.swift`.
- Create: `apple/Apps/iOS/{SCTViOSApp.swift,Info.plist,SCTViOS.entitlements}`, `apple/Apps/macOS/{SCTVmacOSApp.swift,Info.plist,SCTVmacOS.entitlements}`.
- Create: `Sources/SCTVCore/Programmes/{Programme.swift,ContentRef.swift,VideoQuality.swift}`, `Sources/SCTVCore/Playback/{MediaSource.swift,MediaURLPolicy.swift,QualityResolver.swift}`.
- Create: `apple/tool/{check.mjs,sync-fixtures.mjs}`, `apple/README.md`, `apple/AGENTS.md`, `apple/.swift-format`.
- Test: `Tests/SCTVCoreTests/{MediaPolicyTests.swift,QualityResolverTests.swift}`, `apple/tool/check.test.mjs`.
- Modify: root `.gitignore`, `.prettierignore`, `package.json`, `vite.config.ts`, and `README.md` for Apple output exclusions, Markdown checking and watcher exclusion.

**Interfaces:**

- `ContentRef: Hashable, Codable, Sendable` contains string `programmeID`, `dateID`, `contentID`; validated IDs are nonempty decimal strings.
- `VideoQuality: String, Codable, Sendable` has `standard` and `smooth` cases.
- `Programme`, `BroadcastDate`, and `ProgrammeContent` are immutable Codable/Sendable values matching the normalized shared contracts; represent broadcast dates as validated ISO calendar-day strings, not timezone-shifting instants.
- `MediaSource: Equatable, Sendable` contains validated `url: URL`, `quality: VideoQuality`, and `headers: [String: String]`.
- `MediaURLPolicy.validate(_ url: URL) throws -> URL`; `QualityResolver.resolve(_ content: ProgrammeContent, requested: VideoQuality, productVersion: String) throws -> MediaSource`.

- [ ] Write parameterized `MediaPolicyTests.matchesSharedFixture` and `QualityResolverTests.deduplicatesAndFallsBack`. Load the root JSON fixtures without hand-editing copies. Assert `#expect(allowed == fixture.allowed)` and `#expect(source.quality == .smooth)` when only the smooth variant exists and standard is requested. Numeric ID overflow parsing belongs to B1.
- [ ] Create the minimum package/test target declarations and the fixture-copy entry point, then run `node apple/tool/sync-fixtures.mjs` and `swift test --package-path apple/Packages/SCTVKit --filter MediaPolicyTests`; expect missing policy symbols before implementation, not a dependency-resolution or missing-resource error.
- [ ] Implement the exact core interfaces, Referer/product User-Agent construction and policy validation. Create native app targets with deployment floors 26, sandbox/network entitlements, empty fixture-backed SwiftUI roots and shared test schemes. Keep project configuration checked in; no project generator is required.
- [ ] Implement `sync-fixtures.mjs` using Node built-ins to copy all six shared JSON fixtures into ignored test resources before package resolution. `check.mjs` runs this step first, performs package tests and xcodebuild tests, emits result bundles and cleans its own simulators. Add `check.test.mjs` assertions for missing-runtime rejection and subprocess failure propagation. Document direct `swift test` requires fixture sync first.
- [ ] Run both Swift suites, `node --test apple/tool/check.test.mjs`, and the three `check.mjs` platform commands from the index. Expect compiled native roots on each platform; a missing runtime is recorded as unavailable. Because Vite configuration changes, run `pnpm check` and `pnpm build` once for this task. Review boundary: `feat(apple): add native hosts and media contracts` (commit only if authorized).

## Task A2: Bounded range transport and resource loading

**Files:**

- Create: `Sources/SCTVMedia/Transport/{MediaRangeTransport.swift,URLSessionRangeTransport.swift,RangeResponseValidator.swift,AssetResourceLoader.swift,ResourceRequestRegistry.swift}`.
- Create: `apple/tool/{media-server.mjs,make-fixture.swift}`; generated synthetic MP4s live under ignored `apple/build/fixtures/`.
- Test: `Tests/SCTVMediaTests/{RangeTransportTests.swift,ResourceLoaderTests.swift}` and `apple/tool/media-server.test.mjs`.
- Modify: package target definitions to add `SCTVMedia` and its test target; host fixture configuration from A1.

**Interfaces:**

- `ByteRange: Equatable, Sendable` contains `offset: Int64` and `length: Int64?`; reject negative offsets and nonpositive explicit lengths.
- `RangeResponse: Sendable` contains HTTP status, parsed range, total size, MIME type and an `AsyncThrowingStream<Data, Error>` whose producer is bounded and cancelled when consumption ends.
- `MediaRangeTransport.open(source: MediaSource, range: ByteRange) async throws -> RangeResponse`.
- `AssetResourceLoader.makeAsset(source: MediaSource) throws -> AVURLAsset` and `cancelAll()`, confined to its documented serial executor. The loader retains its delegate/request registry for the asset lifetime.

- [ ] Write `RangeTransportTests.rejectsWrongOffset`, `rejectsTruncatedBody`, `rejectsIgnoredRangeForNonzeroOffset`, `cancelsProducerOnConsumerExit` and `ResourceLoaderTests.boundsBufferedBytes`. For a request starting at 4096, assert a response starting at 0 fails; assert `#expect(peakBufferedBytes <= 8 * 1024 * 1024)` across concurrent fixture requests. The 8 MiB cap is transport-retained bytes, not total AVPlayer memory.
- [ ] Run the two suites with `swift test --package-path apple/Packages/SCTVKit --filter 'RangeTransportTests|ResourceLoaderTests'`; expect failure at the named protocol/validation assertions.
- [ ] Implement range validation, exact requested-byte delivery, cancellation and a bounded producer; do not use an unbounded default stream buffer. Permit a `200` response only for an initial zero-offset whole-resource response with validated metadata, and never append it to partial bytes. Reject redirects and malformed Content-Range. Serve content-information requests without downloading the complete asset. Use a private custom scheme only at the AVAsset boundary.
- [ ] Implement a Node fixture server with deterministic `206`, ignored Range, `416`, delayed chunks, redirects and truncated-body scenarios. Generate a short synthetic video with AVAssetWriter via `make-fixture.swift`. Inject the fixture transport through test composition; do not weaken release URL validation or ATS policy. Any localhost test entitlement is confined to the test host/configuration.
- [ ] Run the Swift suites and `node --test apple/tool/media-server.test.mjs`; verify emitted-byte counts and request cancellation. Review boundary: `feat(apple): add bounded AVAsset media transport` (commit only if authorized).

## Task A3: Native player session and feasibility gate

**Files:**

- Create: `Sources/SCTVCore/Playback/{PlaybackRequest.swift,PlaybackSnapshot.swift,PlaybackService.swift}`.
- Create: `Sources/SCTVMedia/Session/{PlayerSession.swift,PlaybackCoordinator.swift,PlaybackObservation.swift}`, `Sources/SCTVMedia/Presentation/{IOSPlayerView.swift,MacPlayerView.swift}`.
- Create: `apple/Tests/{iOS,macOS}/PlayerAcceptanceTests.swift`, `apple/UITests/{iOS,macOS}/PlayerPresentationTests.swift`.
- Test: `Tests/SCTVMediaTests/{PlayerSessionTests.swift,PlaybackOwnershipTests.swift}`.
- Modify: native roots, shared schemes and `check.mjs` to run the fixture player acceptance targets.

**Interfaces:**

- `PlaybackRequest: Sendable` pins `content: ContentRef`, title/programme/broadcast/cover metadata, validated `sources: [MediaSource]`, selected quality, resume milliseconds and speed; local-file requests use an explicit local-source case.
- `PlaybackSnapshot: Sendable` carries session UUID, position/duration milliseconds, quality, speed, play intent and settled/ended state. `PlaybackIntent` has paused/playing cases and is defined beside the snapshot.
- `@MainActor PlaybackService`: `open(_ request: PlaybackRequest) async throws -> UUID`, `setPlaybackIntent(_ intent: PlaybackIntent)`, `setSpeed(_ speed: Double)`, `seek(to milliseconds: Int64) async throws`, `switchQuality(_ quality: VideoQuality) async throws`, `retry() async throws`, `capture() -> PlaybackSnapshot?`, `beginDismissal()`, `cancelDismissal()`, `finishDismissal() async`, and `snapshots() -> AsyncStream<PlaybackSnapshot>`.
- Platform wrappers receive the coordinator-owned AVPlayer; `SCTVFeatures` will receive a presentation factory in B3, never a constructor for another player.

- [ ] Write `PlayerSessionTests.opensPausedAndRestoresAfterSeek`, `closeRevokesQualityResume`, and `PlaybackOwnershipTests.pipRetainsSessionUntilFinished`. Assert `#expect(snapshot.playIntent == .paused)` on open, `#expect(activeSessionCount == 1)` through PiP, and `#expect(releasedObservationCount == registeredObservationCount)` after committed dismissal. Add replacement tests proving old callbacks cannot mutate the new UUID.
- [ ] Run the named suites and observe failures before implementing ownership. Simulated AVPlayer test ports cover deterministic races; fixture-backed acceptance tests exercise actual AVFoundation.
- [ ] Implement the service and platform wrappers, preserving source-selection intent, settled seek semantics and idempotent cleanup. Handle dismissal cancellation and interruption/route loss; retain the session during PiP and release it only at its authoritative lifecycle boundary. A second content intent captures and disposes the old session before replacement.
- [ ] Run the suites and all three platform checks. In native hosts exercise initial readiness, play, forward/backward/near-end seek, variant switch, explicit retry, fullscreen, interactive close and PiP. Test both allowed upstream hosts with HEAD or a small Range request; never download a full upstream programme for a probe.
- [ ] Inspect physical iPhone/iPad PiP and background behaviour, native Mac playback, and sustained synthetic-fixture memory behaviour. Save an acceptance matrix in ignored build output, separating tested, failed and unavailable rows. The transport gate passes only with required platform evidence; revise the design if supported loading fails. Review boundary: `feat(apple): validate native playback lifecycle` (commit only if authorized).

## Exit artifact

A working fixture player and explicit evidence for the transport decision. No catalogue or download UI is required to establish this gate. Continue with [B](2026-10-22-apple-browsing.md) only under the gate rules in the index.
