# Native Apple Client

This is the native SwiftUI programme client, with catalogue/archive browsing, favourites, playback history, settings, downloads and local playback. iPhone/iPad share the iOS target; macOS has a native target. Deployment targets are iOS/iPadOS 26 and macOS 26.

The approved [design](../docs/superpowers/specs/2026-10-22-apple-client-design.md) and [implementation plan](../docs/superpowers/plans/2026-10-22-apple-client.md) retain the acceptance requirements still awaiting device verification. Durable module and lifecycle contracts are in [Apple Architecture](../docs/apple.md). Contribution conventions are in [AGENTS](AGENTS.md).

## Build and check

Use Xcode with the required Apple SDKs and Swift 6.2 or newer. Run commands from the repository root. Open `apple/SCTV.xcodeproj` and select `SCTViOS` or `SCTVmacOS`. Device signing requires your own development team; no team or credentials are stored in the project.

```sh
swift apple/tool/make-fixture.swift
node apple/tool/sync-fixtures.mjs
swift test --package-path apple/Packages/SCTVKit --scratch-path apple/build/swift
node --test apple/tool/*.test.mjs
swift format lint --strict --recursive apple/Packages/SCTVKit/Sources apple/Packages/SCTVKit/Tests apple/Apps apple/UITests
node apple/tool/check.mjs --platform macos --verify-lockfiles
node apple/tool/check.mjs --platform ios --device iphone --os 26 --verify-lockfiles
node apple/tool/check.mjs --platform ios --device ipad --os 26 --verify-lockfiles
```

The fixture generator writes an original 12-second MP4 under ignored `apple/build/fixtures/`. Synchronization copies shared JSON fixtures into package test resources and that MP4 into the test resources and debug host. Run both steps before direct Swift package tests or launching the Xcode project. The checker performs this automatically, runs formatting/package tests, then builds and tests the native host. Logs and XCTest result bundles are written under `apple/build/checks/`.

The checker creates and deletes only its own simulator. An unavailable requested OS returns an error; it never substitutes a newer system. To inspect compatibility with an installed newer runtime, pass its major version explicitly and report that result separately. Mac checks run on the host OS and do not establish compatibility with an older macOS release.

To format Swift sources:

```sh
swift format format --in-place --recursive apple/Packages/SCTVKit/Sources apple/Packages/SCTVKit/Tests apple/Apps apple/UITests
```

## Unsigned release and CI

```sh
node apple/tool/check.mjs --platform macos --configuration Release --verify-lockfiles
node apple/tool/check.mjs --platform ios --configuration Release --verify-lockfiles
```

Release mode compiles without signing, using generic iOS or the host Mac architecture. It does not create a distributable signed archive. Locked mode verifies matching checked-in package/application pins and rejects lockfile changes. GRDB and Nuke are pinned to stable releases in both resolutions.

[Apple CI](../.github/workflows/apple.yml) uses the `macos-26` runner and Xcode 26.6 for Mac, iPhone and iPad validation, plus unsigned Release compilation. Logs and XCTest bundles are retained on failure. A valid workflow does not establish a successful hosted run.

## Current boundaries

The client implements catalogue search/favourites, date archives with explicit snapshot refresh, library/history, appearance and network preferences, durable download state, native background-session integration, file publication/export and local playback. Mac supports external directory authorization and renewal. Platform shells use native navigation and AVKit controls.

Package tests cover media ranges, real AVFoundation fixture sessions, data parsing/storage, snapshot ordering, history, task recovery and file publication. Native UI tests use `--ui-fixtures` to provide deterministic programme data and a synthetic download; the separate `--media-probe` mode verifies loading and seeking. These debug-only fixtures require no upstream traffic and do not verify the operating system's background transfer daemon.

Physical-device and actual OS 26 acceptance remain pending. Local OS 27 checks must be reported separately. Remaining acceptance includes background transfer under suspension/lock/termination, actual PiP/fullscreen/dismissal and audio interruptions, production-network startup/seek performance, sustained memory, large text/VoiceOver and window/rotation continuity, expired external access, low disk space, and actual backup/restore behavior. Hosted CI and signed distribution are also separate checks. See the retained [delivery plan](../docs/superpowers/plans/2026-10-22-apple-downloads.md).
