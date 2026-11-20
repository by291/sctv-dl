# Test Reliability Implementation Plan

**Status:** Completed on 2026-11-21. Retained at the user's explicit request.

> **For agentic workers:** Use focused platform tasks with independent file ownership.
> Apply systematic debugging and test-driven development. The root agent owns integration,
> verification, review, and grouped commits.

**Goal:** Repair false positives, test isolation, missing integration coverage, and unnecessary
test cost identified by the repository-wide review.

**Architecture:** Retain the existing test layers. Exercise production composition through
small shared entry points, keep test-only fixtures with tests, and replace timing guesses
with observable events and bounded waits.

**Tech Stack:** Vitest, Vue, Rust/Tokio/Tauri, Kotlin/Gradle, Flutter/Dart, Swift Testing/XCTest,
GitHub Actions.

**Spec:** [Test reliability design](../specs/2026-11-21-test-reliability-design.md).

## Global Constraints

- Current checkout and branch; no push or deployment.
- Group commits by platform responsibility and CI. Include this plan and its design in a
  separate documentation commit as requested by the user.
- No dependency or toolchain updates. Preserve runtime and serialized compatibility.
- English code-related text; project formatters; readable behavioral tests.
- Do not boot devices in CI. Any local device belongs to this task and is disposable.
- Workers edit only their platform directories and do not stage or commit.
- The root agent owns shared Web files, workflows, repository documentation, and Git.

## Review Focus

- A rejection must identify its actual cause rather than accept any error.
- A test must observe required events before asserting properties of an event collection.
- Cleanup must settle asynchronous work, restore external state, and run after failures.
- Old records must be independent of the current writer and use normal open paths.
- Compile-only checks must include native tests and never implicitly boot a device.

## Task 1: Web isolation and cross-connection notifications

**Files:** `src/shared/composables/usePersistentState.test.ts`, history/cache Web adapter tests,
and focused test support beside their owners if needed.

**Interfaces:** Keep existing adapter ports and BroadcastChannel protocol unchanged.

- [x] Reproduce the storage spy leak with shuffled seed 4682.
- [x] Isolate and explicitly restore Storage fixtures, with cleanup after assertion failure.
- [x] Verify history updates and cache clear notifications between separate adapters without
      requiring the receiving adapter to issue an explicit read; verify disposal.
- [x] Run focused tests, full normal and shuffled Vitest, `pnpm check`, and `pnpm build`.
- [x] Commit as `test(web): isolate storage and verify cross-tab notifications`.

## Task 2: Tauri command and transport tests

**Files:** `src-tauri/tests/`, focused inline tests, command composition in `src-tauri/src/`
only where production registration must be reused.

**Interfaces:** Preserve every command name, DTO, capability, timeout, and native lifecycle.

- [x] Make redirect destinations return successful responses and assert zero target hits.
- [x] Use valid arguments and explicit ACL errors for denied command invocations.
- [x] Reuse production command registration and prove `cancel_request` changes a later
      operation using the same request ID.
- [x] Bound exit-event waits and replace stream/progress sleep assertions with observable
      cancellation and progress gates.
- [x] Reduce cache capacity setup I/O using test-owned disk fixtures while preserving real
      writes at the eviction and durability boundaries.
- [x] Run focused Rust tests, rustfmt, Clippy, full Cargo tests, and desktop adapter tests.
- [x] Commit IPC coverage as `test(desktop): verify ipc permissions and cancellation`.
- [x] Commit transport/cache fixtures as
      `test(desktop): harden transfer fixtures and lifecycle waits`.

## Task 3: Android behavioral fixtures and persisted boundaries

**Files:** `android/` tests, necessary existing composition owners, benchmark, and README.

**Interfaces:** Keep production storage schemas and network policies unchanged. Root owns CI.

- [x] Exercise redirects through the production HTTP client and a successful target.
- [x] Observe mounted intermediate transition state without vacuous empty collections.
- [x] Open a legacy database through the production builder and round-trip settings through
      a disposable real DataStore. Seed independent source/restore download state where relevant.
- [x] Verify failed private cleanup retains identity, and consent completion rejects stale
      attempts/URIs, denial, and cancelled pending authorization.
- [x] Give the scrolling benchmark deterministic long content and verify viewport movement.
- [x] Remove redundant device launches while keeping pixel, lifecycle, and native boundaries.
- [x] Document full test APK compilation and API 31+ animation-enabled theme acceptance.
- [x] Run Spotless, JVM tests, lint/checks, and compile affected instrumentation/benchmark APKs.
- [x] Commit as `test(android): strengthen lifecycle and storage regressions`.

## Task 4: Flutter native assertions and application integration

**Files:** `flutter/` tests, shared test support, platform-host test commands, and README.

**Interfaces:** Preserve production transfer, notification, playback, and storage contracts.

- [x] Subscribe before resume, require actual Range behavior, reject empty progress samples,
      and enforce explicitly requested PiP verification.
- [x] Restore downloads after closing and reopening a disk database seeded with stable old
      records independently of the current codec.
- [x] Inject notification taps into the real application shell and verify downloads routing.
- [x] Reduce duplicated device notice cases; move shared harnesses out of test entry files.
- [x] Give screenshots distinct phase names and deterministic, restored theme state.
- [x] Document native iOS XCTest compilation/execution and explicit capability expectations.
- [x] Run Dart formatting/boundaries/analyzer, normal and shuffled Flutter tests, and compile
      changed native/integration test targets when tools are available.
- [x] Commit as `test(flutter): verify recovery and notification integration`.

## Task 5: Apple asynchronous and interaction assertions

**Files:** `apple/` package/UI tests, test fixtures, tooling only where needed, and README.

**Interfaces:** Preserve production Swift concurrency and native resource contracts. Root
owns CI changes; coordinate any test-build command interface before editing tooling.

- [x] Distinguish redirect rejection from following and verify cancellation stops body work.
- [x] Bound request/stream waits and drain snapshot observation before stale-update assertions.
- [x] Replace even-toggle parity with observable rapid-click effects and synchronize native
      window/control operations using their resulting state.
- [x] Verify preserved legacy field values through the normal database factory.
- [x] Reduce redundant UI setup while retaining native focus, sizing, and playback evidence.
- [x] Run Swift formatting, package tests, Node tooling tests, and compile UI test targets.
- [x] Commit as `test(apple): make concurrency and interaction checks deterministic`.

## Task 6: Native test compilation gates and integration review

**Files:** `.github/workflows/android.yml`, `.github/workflows/flutter.yml`,
`.github/workflows/apple.yml`, Apple/Flutter build tooling if needed, `docs/maintenance.md`.

**Interfaces:** Android must assemble all relevant test APKs. Apple and Flutter iOS must use
compile-only test actions with generic destinations and no simulator creation or launch.

- [x] Add explicit host-only native test compilation commands using existing locked tools.
- [x] Update verification ownership and platform guide commands consistently.
- [x] Run tooling tests, formatting, docs checks, workflow lint, and available native builds.
- [x] Review the complete diff independently and repair material findings.
- [x] Commit as `ci(native): compile platform test targets without devices`.

## Additional Reliability Repair

- [x] Settle Vite dependency optimization before disposing startup-test directories.
- [x] Commit as `test(tooling): await dependency optimization before cleanup`.

## Targeted Native Acceptance Follow-ups

- [x] Verify Apple archive and downloads rapid input on a disposable iOS runtime.
- [x] Replace selection-overlay absence with actual playback and return behavior.
- [x] Commit as `test(apple): verify playback after leaving selection`.
- [x] Exercise Android native Range retry and exact full-response bytes.
- [x] Review and commit the Android retry fixture and documented runtime limits.
- [x] Commit as `test(flutter): verify native resume after interrupted transfers`.

## Execution Record

Detailed commands, diagnostics, per-run evidence, and execution limits belong to ignored
build outputs. Keep reusable verification procedures in the owning platform guides.
