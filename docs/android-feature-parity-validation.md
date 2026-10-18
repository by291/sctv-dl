# Android Feature Parity Validation

Evidence recorded on 2026-10-17 for the native Android implementation. The maintained product contracts are in [Client Design](android-client-design.md) and the [Android README](../android/README.md). The approved design and implementation plan were committed as `026b639`; implementation commits are grouped by responsibility in the original checkout.

## Responsibility Review Follow-up (2026-10-18)

The Android responsibility/readability review is implemented without changing module edges, persistent schemas, preference keys or route names. Archive confirmation now retains accepted download/history context; settings/favourite writes and programme observations expose recoverable errors. Media3 initialization releases partial resources after failure or cancellation. Download reconciliation/action stages, network access, player session binding, control visibility and navigation state/motion have explicit owners. Persistence mappings use named fields, and contract comments explain acceptance, revision, lease and cleanup boundaries.

`spotlessCheck check :app:assembleDebug :app:assembleRelease` passed, including 141 JVM cases, Android lint and dependency-boundary checks. Documentation formatting, local links and diff whitespace passed. The independent whole-diff review reported no production findings; its coverage suggestions were added for invalid selections, failed membership/context/content observations, cancellation and stale errors. The new native cache tests reproduced locked-cache retries before the fix and passed afterward.

| Module               | API 29 follow-up                                              | API 37 follow-up                                   |
| -------------------- | ------------------------------------------------------------- | -------------------------------------------------- |
| `core:data`          | 20/20 passed                                                  | Not repeated                                       |
| `core:ui`            | 2/2 passed                                                    | Not repeated                                       |
| `core:player`        | 15/16 passed; decoded-frame pixel assertion fails             | All four native session cases passed               |
| `feature:player`     | 14/14 passed                                                  | Not repeated                                       |
| `feature:programmes` | 54/54 passed                                                  | Not repeated                                       |
| `feature:downloads`  | 10/10 passed                                                  | Not repeated                                       |
| `feature:settings`   | Four applicable cases passed; dynamic colour requires API 31+ | Dynamic colour and new retry-feedback cases passed |
| `app`                | 24/25 passed; existing fullscreen status-bar assertion fails  | Fullscreen/exit/disposal case passed               |

The two API 29 failures were also reproduced against an isolated copy of committed baseline `b80d3d4`, with the same assertions (including decoded pixel `ff008800`). Their original fixtures/assertions remain unchanged. Complementary runs cover 147 distinct device cases successfully, but neither a green unfiltered API 29 suite nor a full API 37 run is claimed. Both AVDs were disposable and explicitly selected; no user emulator or whole upstream episode was used. New retry feedback was inspected at 320 dp and 200% text in light/dark themes, including keyboard activation. Existing suites covered adaptive layout, loading/empty/error states, restoration, predictive navigation, gestures, artwork and destination lifetime. Physical-device performance, OS backup, signing and publication were outside this review.

## Implemented Scope

- Exact-identity viewing history, paused resume, online/local shared progress, legacy local fallback, search, removal, and a deterministic 500-entry limit.
- A separate user database for favourites/history, transactional legacy import, backup eligibility, and independent history/cache maintenance.
- Managed Media3 downloads with pause/resume, durable attempts, per-task network policy, execution leases, deferred recovery, and preserved legacy DownloadManager tasks.
- Recoverable MediaStore publication, publication-only retry, separate record/file deletion, and immutable batch targets with partial-result reporting.
- Download filters, complete metadata and real covers, accessible actions, quality-switch rollback, and compact player controls with stable time widths.

## Automated Checks

From the repository root, using JDK 21 and the configured Android SDK:

```sh
./android/gradlew -p android spotlessCheck check :app:assembleDebug :app:assembleRelease :app:assembleDebugAndroidTest
pnpm format:check
git diff --check
```

The Android unit, lint, module-boundary and application build checks passed. JUnit results contain 117 passing JVM tests: 103 Android-module debug unit tests and 14 pure JVM tests. Both debug and unsigned release APKs build. No dependency versions, application IDs, saved preference keys, or version-1 runtime schema were changed. Web/Flutter/Tauri runtime code was not modified, so their application builds were outside this change's verification scope.

## Device Evidence

Testing uses separate disposable API 29 and API 37 AVDs, always selected with `ANDROID_SERIAL`. Local MockWebServer fixtures and small generated media exercise transfer behaviour; no complete upstream episode was downloaded for testing. Modules run sequentially on each device to avoid competing test activities.

```sh
ANDROID_SERIAL="$SCTV_QA_SERIAL" ./android/gradlew -p android \
  :core:data:connectedDebugAndroidTest \
  :core:player:connectedDebugAndroidTest \
  :feature:player:connectedDebugAndroidTest --no-parallel

ANDROID_SERIAL="$SCTV_QA_SERIAL" ./android/gradlew -p android \
  :feature:programmes:connectedDebugAndroidTest \
  :feature:downloads:connectedDebugAndroidTest \
  :feature:settings:connectedDebugAndroidTest \
  :app:connectedDebugAndroidTest --no-parallel --continue
```

Recorded module outcomes:

| Module               | API 29                                                                                                      | API 37                                                    |
| -------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `core:data`          | 18/18 passed                                                                                                | 18/18 passed                                              |
| `core:player`        | Not repeated                                                                                                | 4/4 passed                                                |
| `feature:player`     | Not repeated                                                                                                | 11/11 passed                                              |
| `feature:programmes` | 47/48 in the final broad run; the remaining date-dialog selector was corrected and passed its focused rerun | Compose coverage uses API 29                              |
| `feature:downloads`  | 4/4 passed                                                                                                  | Not repeated                                              |
| `feature:settings`   | Three applicable cases passed across runs; one Android 12+ case is ineligible                               | 3/4 passed; storage-confirmation test blocked by Espresso |
| `app`                | 19/20 passed; status-bar visibility assertion remains                                                       | 16/20 passed; two Espresso and two gesture-inset failures |

The date-dialog correction matches the radio option's role as well as its date. The previous text-only matcher could select both the underlying date chip and the open sheet; this changed only the test's target selection.

The following boundaries have direct regression coverage:

| Boundary              | Observable evidence                                                                                                                                                                                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| User persistence      | Interrupted import rolls back; restored import authority preserves removed favourites; exact date/content identities remain distinct; old sessions cannot overwrite new progress or recreate cleared rows; history is capped at 500.                                 |
| User-only restore     | A copied, closed user database opens against a clean runtime and retains favourites/history without restoring download jobs. This is a database fixture, not a platform backup/restore run.                                                                          |
| Legacy upgrade        | Room validates the version-1 to version-2 migration and preserves legacy transfer IDs, URI references, active reservation and byte progress. The fixture does not perform an OS upgrade of a live system transfer.                                                   |
| Transfer lifetime     | Native cached transfer survives manager recreation; restored queued/removing entries cannot start network traffic without a context/lease; withdrawing a lease cancels a Call even after response headers arrive.                                                    |
| Recovery              | Recoverable network failure waits for a later lease with the same attempt/cache; incompatible content requires explicit retry. Validator tests reject unsafe resume responses.                                                                                       |
| Public file integrity | A controlled 2 MiB transfer pauses, recreates its manager, resumes with Range, publishes an owned MediaStore file, verifies all bytes, and deletes it. Pending rows are found again after recreation.                                                                |
| Publication failure   | Failed publication retains private data for local retry. Record removal cleans private resources while preserving public media; stale attempts cannot act on replacement tasks.                                                                                      |
| History/player        | Recorder tests cover throttling, paused buffered seeks and invalidation. ViewModel tests cover resume context; device history search/back/open retains the correct target. Native player tests cover lifecycle and source replacement.                               |
| Playback recovery     | Controller tests cover one rollback, retained retry context, intervening pause, external play/pause, and single-action replay after end.                                                                                                                             |
| Download interaction  | Device tests cover filters, confirmation, task actions, large text and stale batch selections. A failed batch item does not prevent later items from completing.                                                                                                     |
| Storage               | Late metadata responses cannot refill a cleared cache. Cleanup reports independent failures. Device tests verify separate history/cache confirmation.                                                                                                                |
| Controls              | Light/dark and 200% text coverage verifies stable hour-boundary geometry, horizontal reachability, 48 dp buttons, and single-quality inspection without source reload. Existing overlay/window tests exercise focus, menus, auto-hide, fullscreen and PiP ownership. |

Native publication testing exposed two platform details now covered by the fixture: collection queries must explicitly include pending MediaStore rows, and API 29 can update its `SIZE` metadata after file finalization. Completion checks use the owned file descriptor's actual size plus readability.

## Review and Execution Decisions

An independent whole-change review identified seven issues. All were resolved with focused regressions: restored native execution without a context, cancellation after HTTP headers, transient network failure recovery, private-cache cleanup on record removal, ended-video replay, external transport intent, and paused seeks during buffering.

Media3 remains responsible for transfer and caching. Application service/job leases grant execution permission; jobs never start a background foreground service. Native progress can retract an uncommitted buffer after process recreation, so integrity assertions compare resumed bytes and the completed file rather than requiring a transient progress sample to persist exactly.

## Coverage Limits

- API 37's pinned Espresso integration fails two app Compose tests and the settings storage-confirmation test with `NoSuchMethodException: android.hardware.input.InputManager.getInstance`. Those tests pass on API 29. Two navigation-inset assertions also fail on the generic API 37 AVD, which has no bottom navigation inset, and pass on the API 29 Pixel fixture.
- The existing API 29 app playback-host test encountered a status-bar visibility assertion; its API 37 run passed. The Android 12+ dynamic-colour test is intentionally ineligible on API 29 and passes on API 37. Complementary device runs do not establish an entirely green, unfiltered suite on both API levels.
- Backup rules and user-only database restore were verified, but cloud backup and OS device transfer were not exercised. Version-1 database migration is not evidence of an OS upgrade with a real active DownloadManager job or an externally owned completed file.
- Real VPN/cellular transitions, manufacturer background policies, prolonged system execution quotas, system-mediated consent for another owner's video, and a delayed Coil response during cache cleanup have not been verified on physical devices. Network/lease, consent identity and metadata-generation rules have focused regression coverage; image generations were inspected in code.
- No performance measurements, signed release, publication, push, or deployment were performed.

## Workspace and Cleanup

Work continued in the original repository after the user declined worktrees. The temporary worktree was archived only after its files were copied and verified. The completed plan/spec were removed after extracting their maintained contracts into the linked documentation; their approved versions remain in commit `026b639`.

Temporary API 37 display overrides were reset to the AVD's original size/density and checked through both reported values and a screenshot. API 29 retained its original display configuration. Only the task-owned disposable AVDs were stopped and removed; user devices were not used for tests.
