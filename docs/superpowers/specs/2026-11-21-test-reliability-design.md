# Test Reliability Repair Design

## Status and authorization

Completed on 2026-11-21. Retained with the implementation plan at the user's explicit
request. The user approved the review repairs and requested grouped commits in the
current checkout and branch.

## Intent

Repair every actionable category in the repository-wide test review: behavioral value,
test layers, fixture suitability, duplication, missing coverage, cost, and reliability.

## Approach

Strengthen existing behavioral tests and reuse real production composition at integration
boundaries. Use controlled local services, disposable storage, explicit event gates, and
bounded waits. Preserve meaningful lower-layer coverage and reduce repeated device work.

Broad test rewrites would obscure existing regressions. Increasing timeouts would preserve
false-positive paths. Neither approach addresses the reviewed defects.

## Required outcomes

- Web storage failure fixtures cannot leak between tests. Cross-connection history and cache
  notifications exercise BroadcastChannel delivery and disposal.
- Native redirect tests distinguish rejection from following a successful destination.
  Android tests use the production HTTP client configuration.
- Tauri IPC tests use valid per-command arguments, explicit permission rejection, real
  command registration, and observable cancellation effects.
- Flutter transfer and opt-in PiP tests cannot silently omit required assertions. Subscribe
  before actions that can emit terminal events.
- Android and Apple interaction tests observe meaningful intermediate states or effects;
  empty samples and even-number toggle parity cannot prove correctness.
- Asynchronous test fixtures have bounded waits and cancellation-aware cleanup. Snapshot
  assertions wait for the observer to consume the relevant updates.
- Storage compatibility uses stable legacy records and normal production open paths.
  Include real disk reopen, migration registration, and settings persistence boundaries.
- Add the missing Flutter application notification navigation boundary and Android download
  consent and failed-cleanup regressions.
- CI compiles native test targets without booting devices or invoking native GUI tests.
  Platform guides document explicit local device commands and capability requirements.
- Android scroll measurement uses reproducible, sufficiently long fixture content and
  verifies actual scroll movement. Reduce duplicated device cases and costly fixture setup
  while retaining native-only assertions and real persistence operations.

## Constraints

- Preserve IPC payloads, storage keys, migration schemas, product behavior, and resource
  ownership. Production changes are limited to sharing existing composition when needed.
- No dependencies, toolchain upgrades, new branches, worktrees, pushes, or deployments.
- Use project formatters and English code-related text. Owned code follows the user's
  readability requirements, including 100-column lines and explicit control flow.
- Use disposable test resources. Do not use existing user emulators or simulators.
- Keep suite success, target compilation, device execution, and hosted CI separate claims.

## Acceptance

Run the relevant host suites, shuffled Web and Flutter suites, formatters, static checks,
native test compilation, and workflow validation. For repaired false-positive tests,
demonstrate a representative incorrect behavior is detected when practical. Record exact
commands and unavailable device coverage in ignored verification output.

## Native acceptance refinements

Actual device execution identified two fixture assumptions that needed further repair:

- Apple download selection keeps its overlay mounted. Verify that a playback-card tap opens
  the player and returns to browsing instead of requiring that overlay to disappear.
- On Android, verify retry-based resume after an intentional partial-response interruption.
  Require a positive Range, a completed full HTTP 200 response, and exact file bytes. The
  pinned downloader's manual-pause socket race remains a documented runtime limitation.
  Keep the iOS explicit pause/resume fixture on a valid HTTP 206 response.

Native execution limits remain in the platform guides and ignored acceptance reports.
Passing compile-only gates does not establish device behavior or hosted CI results.
