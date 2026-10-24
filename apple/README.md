# Native Apple Client

This is the native SwiftUI programme client, with catalogue/archive browsing, favourites, playback history, settings, downloads and local playback. iPhone, iPad and native Mac share the `SCTV` multiplatform application target and the `SCTVUITests` target. Deployment targets are iOS/iPadOS 26 and macOS 26.

Module and lifecycle contracts are in [Apple Architecture](../docs/apple.md). Contribution conventions are in [AGENTS](AGENTS.md); repository-wide CI and dependency policy belongs to [Repository Maintenance](../docs/maintenance.md).

## Toolchain and signing

Use Xcode with the required Apple SDKs and Swift 6.2 or newer. Run commands from the repository root. After preparing dependencies and fixtures below, open `apple/SCTV.xcodeproj`, select the `SCTV` scheme, and choose an iPhone, iPad or My Mac destination. Device signing requires your own development team; no team or credentials are committed.

For local signing, copy the template once and replace `YOUR_TEAM_ID` with your Apple Developer Team ID:

```sh
cp apple/Configuration/Signing.local.xcconfig.example apple/Configuration/Signing.local.xcconfig
```

`Configuration/Signing.xcconfig` is the shared base configuration for Debug and Release. It optionally includes the Git-ignored `Signing.local.xcconfig`; the application and UI test targets inherit that team on iOS, iPadOS and macOS. Edit the local file when changing teams instead of selecting a team in Xcode's Signing & Capabilities pane, which can write a target override back into `project.pbxproj`. Certificates and private keys remain in the macOS keychain. A fresh checkout without the local file can still use the unsigned build commands below. Signed CI builds can supply `DEVELOPMENT_TEAM` as an `xcodebuild` command-line setting.

Debug builds install as `SCTV Debug`, with bundle identifiers `dev.sctvdl.apple.ios.debug` and `dev.sctvdl.apple.mac.debug`. Release builds retain `SCTV` and the original identifiers without the `.debug` suffix. Both configurations can coexist with separate sandbox data; existing installations under the original identifiers remain associated with Release. The tracked Products reference uses `SCTV Debug.app`, matching the bundle name Xcode writes during Debug development. This reference is shared project metadata and can be committed; configuration-specific `PRODUCT_NAME` and bundle identifiers still determine the actual output. Do not ignore `project.pbxproj` or hide its changes to suppress this metadata update; local signing remains in the ignored xcconfig.

## Dependencies and fixtures

`Packages/SCTVKit/Package.resolved` is the canonical checked-in resolution, with GRDB and Nuke pinned to stable releases. Dependabot updates this file and `Package.swift` together. `node apple/tool/lockfiles.mjs` generates the ignored Xcode resolution from those pins; run it before opening Xcode or after dependency updates when not using the checker. The generated file uses the supported version-2 pin format without copying the package manifest's graph-specific `originHash`. Locked checks reject changes to the canonical file and verify that Xcode retains the same package identities, locations, versions and revisions; Xcode-only metadata changes are allowed. Do not update or commit the generated application lock separately.

The checker prepares the Xcode lock and fixtures automatically. For direct Xcode use or focused Swift package tests, prepare them from the repository root:

```sh
node apple/tool/lockfiles.mjs
swift apple/tool/make-fixture.swift
node apple/tool/sync-fixtures.mjs
```

The fixture generator writes an original 12-second MP4 under ignored `apple/build/fixtures/`. Synchronization copies shared JSON fixtures into package test resources and that MP4 into test resources and the Debug host. Do not hand-edit generated fixture copies.

## CI and unsigned Release builds

These are the commands used by Apple CI:

```sh
node --test apple/tool/*.test.mjs
node apple/tool/check.mjs --platform all --configuration Release --verify-lockfiles
```

Release mode compiles without signing, using generic iOS or the host Mac architecture. `--platform all` requires Release and runs formatting/package tests once before compiling both platforms. It never starts a simulator or runs native UI tests, and it does not create a distributable signed archive. Individual `--platform macos` and `--platform ios` Release commands remain available.

[Apple CI](../.github/workflows/apple.yml) uses the `macos-26` runner and Xcode 26.6 for tooling tests, Swift formatting, package tests and unsigned macOS/iOS Release compilation. It does not start simulators or execute native UI tests; the [Debug commands below](#local-native-ui-checks) remain local acceptance checks. Logs and build result bundles are retained even on failure. A valid workflow does not establish a successful hosted run.

## Local native UI checks

Debug mode runs formatting, package tests and native UI tests. Use it for affected interaction and lifecycle changes:

```sh
node apple/tool/check.mjs --platform macos --verify-lockfiles
node apple/tool/check.mjs --platform ios --device iphone --os 26 --verify-lockfiles
node apple/tool/check.mjs --platform ios --device ipad --os 26 --verify-lockfiles
```

The iOS checker creates and deletes only its own simulator. An unavailable requested OS returns an error; it never substitutes a newer system. To inspect compatibility with an installed newer runtime, pass its major version explicitly and report that result separately. Mac checks run on the host OS and do not establish compatibility with an older macOS release.

Logs and XCTest/build result bundles are written under `apple/build/checks/`. Inspect runtime diagnostics as well as test assertions, especially SwiftUI state-update warnings during selection, alerts and native presentation changes.

## Focused tests and formatting

After preparing fixtures, run package tests directly; append `--filter <suite-or-test>` to select focused coverage:

```sh
swift test --package-path apple/Packages/SCTVKit --scratch-path apple/build/swift --force-resolved-versions
swift format lint --strict --recursive apple/Packages/SCTVKit/Sources apple/Packages/SCTVKit/Tests apple/Apps apple/UITests
```

To format Swift sources:

```sh
swift format format --in-place --recursive apple/Packages/SCTVKit/Sources apple/Packages/SCTVKit/Tests apple/Apps apple/UITests
```

## App icons

The shared `Apps/Shared/Assets.xcassets/AppIcon.appiconset` supplies the iPhone, iPad and Mac launcher icons for both build configurations. Regenerate the warm-red television artwork with `swift apple/tool/generate-icons.swift` from the repository root. The generator reuses the Flutter television mark with the Apple client's light appearance accent, exports an opaque 1024-pixel iOS master, and renders the Mac sizes with a transparent outer margin. Commit the generated assets with generator changes; builds do not run the generator.

## Verification scope

Package tests cover media ranges, real AVFoundation fixture sessions, data parsing/storage, snapshot ordering, history, task recovery and file publication. Native UI tests use `--ui-fixtures` to provide deterministic programme data and a synthetic download; the separate `--media-probe` mode verifies loading and seeking. These debug-only fixtures require no upstream traffic and do not verify the operating system's background transfer daemon.

Report the commit, toolchain, OS, device and observed scenario with each verification result. Compilation, package tests, fixture UI tests, physical-device behaviour and hosted CI establish different scopes; none implies signed distribution or complete release acceptance. Use synthetic media for complete playback and transfer tests, and HEAD or a small Range request for live upstream probes. Keep logs, screenshots and recordings in ignored build output or CI artifacts.
