# Native Apple Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user selects the execution method after reviewing this plan.

**Goal:** Deliver an independent native SwiftUI programme client for iPhone, iPad and Mac with durable playback history and downloads.

**Architecture:** Two application targets compose five local package targets. Core contracts separate features from HTTP, SQLite, playback and background-transfer implementations. Platform shells own navigation and application lifecycle.

**Tech Stack:** SwiftUI, Observation, Swift Concurrency, URLSession, AVFoundation/AVKit, GRDB, Nuke/NukeUI, Swift Testing and XCTest.

**Spec:** [Approved Apple design](../specs/2026-10-22-apple-client-design.md).

Status: Written for review on 2026-10-22. No execution tasks have started. Paths, interfaces and commands below describe future deliverables, not existing files or successful checks.

## Global Constraints

- Minimum systems: iOS 26, iPadOS 26 and macOS 26. Use Swift 6 language mode and a Swift tools 6.2 package manifest; do not introduce APIs requiring a later OS without availability handling.
- The macOS target is a native Mac application, not a Catalyst build. iPhone and iPad share the iOS target.
- Applications connect directly to upstream services. A Node deployment is not a normal runtime dependency.
- `SCTVCore` has no SwiftUI, AVKit or database dependency. Features consume core protocols; applications construct implementations.
- Documentation, comments and test descriptions are English; product copy is Chinese.
- Top-level destinations are 栏目, 资料库 and 下载. Opening content starts paused. The first release permits one active playback session per application.
- Metadata bodies are limited to 2 MiB. History retains the newest 500 entries; save advancing progress at five-second intervals. Completion is ended or at least 95% of a known positive duration.
- Download batches accept at most 100 distinct items. Attempt identity fences retries and callbacks. File publication is separate from transfer completion.
- No unsupported AVURLAsset header option, full-episode buffering, silent online fallback for missing local files, or automatic migration/synchronization with other clients.
- Preserve existing clients and current uncommitted documentation. Local commits, push and signed release remain subject to the user's explicit authorization; suggested commit subjects are review boundaries, not permission to commit.

## Review Focus

These cross-cutting cases are assigned explicit tests in the phase plans:

1. A media server ignores Range, lies about its length, or stops mid-body: no corrupt seek, unbounded buffering or false readiness (A2).
2. A cancelled request finishes after switching programme/date: no stale data or selection mutation (B2).
3. A window dismisses during quality replacement, or PiP outlives its source view: no surprise playback or premature release (A3, B4).
4. The process stops between native enqueue, callback and database commit: no duplicate task or lost recoverable file (C1, C2).
5. External directory access is revoked or the completed file disappears: staged bytes survive; the user sees actionable recovery, never a fake completed/local-playable state (C3).

## Delivery sequence

| Plan                                                       | Tasks | Independently reviewable result                                    | Gate                                                                              |
| ---------------------------------------------------------- | ----- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| [A: Media and foundation](2026-10-22-apple-media.md)       | A1–A3 | Buildable platform hosts and verified candidate playback transport | Required transport works on all three platforms; real-device gaps remain explicit |
| [B: Browsing and playback](2026-10-22-apple-browsing.md)   | B1–B4 | Usable catalogue/archive/library with durable settings and history | Native navigation and player ownership pass platform acceptance                   |
| [C: Downloads and delivery](2026-10-22-apple-downloads.md) | C1–C4 | Durable downloads, offline files and reproducible validation       | Recovery tests and device matrix complete; signing remains separate               |

Execute in order. A failed media gate stops expansion into B/C until its design is revised. A missing physical device is an unverified gate, not a pass; independent unit-test work may continue, but no claim of complete media or release acceptance is allowed. Each phase consumes the earlier phase's named interfaces.

## File ownership map

All paths in the phase plans are repository-relative. Within the package, `Sources/<target>/` and `Tests/<target>Tests/` are rooted at `apple/Packages/SCTVKit/`. Brace lists identify concrete files to create, not wildcard permission to edit unrelated files.

| Owner                   | Files and responsibilities                                                                                              |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Application composition | `apple/Apps/{iOS,macOS}/`: entry points, dependencies, navigation, platform lifecycle and native entitlements           |
| Core                    | `SCTVCore/{Programmes,Playback,History,Downloads,Preferences}/`: immutable values, typed states, policies and protocols |
| Data                    | `SCTVData/{Network,Storage,Programmes,History,Preferences}/`: decoding, bounded transport, migrations and repositories  |
| Media                   | `SCTVMedia/{Transport,Session,Presentation}/`: range loading, player ownership and UIKit/AppKit wrappers                |
| Downloads               | `SCTVDownloads/{Queue,Transfer,Files}/`: durable attempts, native callbacks, staging and publication                    |
| Features                | `SCTVFeatures/{Catalogue,Archive,Library,Downloads,Settings,Design}/`: views, page models and presentation rules        |
| Build and tests         | `apple/SCTV.xcodeproj/`, `apple/Tests/`, `apple/UITests/`, `apple/tool/` and package tests                              |
| Durable documentation   | `apple/README.md`, `apple/AGENTS.md`, `docs/apple.md` and the root documentation index                                  |

Create directories only when a task gives them content. Keep pure policies beside their domain, native cleanup beside its owner, and tests beside the package target they exercise.

## Verification conventions

Commands run from repository root. The following are contracts for scripts introduced in A1/C4, not commands to execute during this planning change:

```sh
swift test --package-path apple/Packages/SCTVKit --filter SuiteName
swift format lint --strict --recursive apple/Packages/SCTVKit/Sources apple/Packages/SCTVKit/Tests apple/Apps
node apple/tool/check.mjs --platform macos
node apple/tool/check.mjs --platform ios --device iphone --os 26
node apple/tool/check.mjs --platform ios --device ipad --os 26
```

`SuiteName` is replaced by the exact suite in each task. An expected red test is a named assertion failure after its test target builds, or an explicitly missing new symbol during the first contract task; package resolution/toolchain failures are not red-test evidence. A green result requires a nonzero executed-test count and exit zero. UI checks require result bundles and inspected screenshots, not just a build.

`check.mjs` must select an available matching runtime deterministically, create only disposable simulators, record the selected OS, and remove its simulators in `finally`. Missing OS 26 must report unavailable instead of silently testing a later OS. Preserve the user's simulators and preferences. Output belongs in ignored `apple/build/`.

Observed locally during planning: Xcode 27.1 and Swift 6.4. These observations do not establish OS 26 compatibility or available simulators. Execution must inspect available SDKs/runtimes and physical devices again. Keep target deployment floors at 26 and separately report minimum-OS and current-OS runs.

## Review and completion rules

- [ ] Review all three phase plans against the approved design and choose inline or subagent execution.
- [ ] At each task, write the named regression test, observe the intended failure, implement its owner, and run the named checks.
- [ ] Review the task diff before continuing; create the suggested local commit only if the user has authorized commits.
- [ ] Record failed/unavailable gates and their evidence in ignored build output and the execution report.
- [ ] After C4 acceptance, migrate durable decisions to their owning guides, update README links, and remove this plan and superseded spec. Do not remove them while work remains incomplete.

Recommended execution method: inline for the first implementation, because the media decision gates every later feature and the tasks share closely coupled contracts. A final independent review can follow the completed implementation; do not dispatch agents during planning.
