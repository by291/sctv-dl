# Android Feature Parity Design

Status: Approved by the user on 2026-10-17. Product implementation has not started.

Prepared on 2026-10-17. This design covers the user's request to implement all Android gaps identified against the current Flutter client. The existing [Android design](../../android-client-design.md), [Android instructions](../../../android/AGENTS.md), and [Flutter product behaviour](../../../flutter/README.md) remain the baseline.

## Outcome and Scope

Bring the Kotlin Android client's everyday viewing and download management up to the current Flutter feature set while preserving installed user data, public downloaded files, and active legacy transfers.

The approved feature scope includes:

- Searchable viewing history, durable resume positions, completion state, individual removal, and history clearing.
- Download filters, selection, batch actions, individual and batch file deletion, and better task cards.
- Manual download pause/resume with truthful task capabilities and durable recovery.
- Metadata/image cache cleanup that preserves user data and downloaded media.
- Quality-switch failure recovery that restores the previous usable source and playback context.
- System backup and device transfer eligibility for favourites and viewing history.
- Flutter-style compact player controls and download artwork/metadata presentation.

Existing search, favourites, archive dates, accepted-versus-pending refresh state, Media3 playback, explicit PiP, file sharing, and adaptive navigation remain supported. Flutter, Web, and Tauri product behaviour is outside this change. No commit, push, signing, or deployment is included in the implementation authorization.

## Architecture Decision

Keep the existing Kotlin/Compose modules and repository boundaries. Introduce focused history, storage-maintenance, and managed-transfer contracts in `core:domain`; implement them in `core:data`. History presentation belongs in `feature:programmes`; navigation and concrete platform composition remain in `app`. Player session mechanics remain in `core:player`.

### Download Options

| Option                                                         | Benefit                                                                             | Cost                                                                                                      | Decision                              |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| Retain platform DownloadManager for every task                 | Preserves the existing background service and public-file workflow                  | Does not provide public manual pause/resume controls                                                      | Insufficient for the complete request |
| Use Media3 downloads for new tasks and retain a legacy adapter | Reuses the project's existing maintained media stack and its durable download index | Requires public-file publication, service scheduling, network-policy enforcement, and upgrade coexistence | Recommended                           |
| Implement a separate HTTP transfer engine                      | Full control over file layout and per-task behaviour                                | Adds resumability, integrity, process recovery, and service ownership that a library already provides     | Not selected                          |

Media3 owns managed transfer execution, cache spans, stopping/resuming, and transfer indexing. The application owns accepted programme context, attempt identity, network policy, UI state, public-file publication, and legacy compatibility. Do not add a second application HTTP download loop.

## Viewing History and Resume

Introduce a platform-neutral content reference containing programme ID, broadcast-date ID, and content ID. Retain an immutable accepted selection containing the title, programme name, broadcast date, actual artwork, and available variants. This selection is shared through domain contracts rather than feature-to-feature imports.

History stores the content reference, accepted metadata, last position, optional known duration, last viewed time, and completion state. Online and newly downloaded copies of the same content share one history record. Keep the newest 500 entries, with deterministic ordering for equal timestamps.

- Save advancing progress no more often than once every five seconds, plus pause, completed seek, backgrounding, completion, and committed route exit.
- Serialize durable writes so an older periodic update cannot overwrite a later exit position.
- Mark an ended video, or a position at least 95% through a known positive duration, completed.
- Open incomplete content at its saved position while remaining paused. Completed content opens at zero. Resume preparation must not briefly display an unrelated opening frame.
- Retain `SavedStateHandle` for restoration of a live navigation entry; it does not replace durable per-content history.
- A history persistence failure is visible and retryable without blocking otherwise valid playback.

Add a library toolbar history entry and a secondary history destination. Support search, local viewing-day groups, known progress, resume/replay actions, individual removal, and retained search/scroll state. Back closes search before leaving the page. Settings provides a separately confirmed clear-history action. Clearing/removing history invalidates older queued writes; subsequent genuine viewing may create a new record.

Legacy downloaded tasks lack programme/date IDs and artwork. Preserve their local playback and record identity. Use a legacy task-scoped resume record until an exact content reference is available; do not guess IDs from a title or merge unrelated broadcasts. New requests persist complete accepted identity and artwork.

## Storage, Upgrade, and Backup

Keep the existing `sctv-metadata.db` filename and its version-1 schema as an explicit migration source. Use forward Room migrations for additional download columns and states; never use destructive migration. Existing serialized enum values, task IDs, DataStore keys, application IDs, and route names remain readable.

Introduce a separate Room user database for favourites, history, and migration metadata. Settings remain in their existing DataStore. Metadata snapshots, transfer indices, private transfer caches, installation identity, and public-video references remain outside the backup allowlist.

Before exposing the new favourites repository, transactionally copy legacy favourites into the user database and write an import-complete marker in that same database. Re-running initialization after an interrupted import must be harmless. An existing/restored user database with the completed marker is authoritative, so deleted favourites are not resurrected from the retained legacy table. Delay favourite mutations until import has finished.

Update cloud-backup and device-transfer rules to include the user database and its journal files, together with the existing settings. Do not claim backup or restore occurred merely because a file is eligible. Restoring user data must not recreate transfer jobs, restore stale system IDs, or claim local files exist on another device.

## Download Identity and Lifecycle

Extend the durable task record with transfer-owner kind, current attempt ID, revision, accepted content reference/context, private resource identity, publication state, and capability information. New fields have explicit migration defaults identifying old records as legacy platform tasks.

Persist preparation and an active content/actual-quality reservation before starting a managed transfer. Each new attempt has its own transfer identity, cache key, and unique safe destination filename. Paused, waiting, and finalizing tasks retain the active reservation. Preserve per-item submission failures and requested-versus-actual quality reporting.

Use typed results/capabilities for actions rather than deriving capabilities solely from button labels. Display preparing, queued, downloading, waiting, paused, finalizing, completed, failed, cancelled, interrupted, and missing outcomes with actual reasons and byte counts. Unknown totals stay indeterminate.

Old platform jobs continue under their original system IDs and existing reconciliation logic. Do not cancel or duplicate them during upgrade. Old completed URIs remain usable. Pause/resume is unavailable for legacy jobs and the UI explains that capability when needed. An explicit retry or redownload creates a new managed attempt only after the old attempt is safely terminal or removed.

### Pause, Resume, and Background Ownership

Use persisted per-download Media3 stop reasons for a user's pause. Do not implement durable pause with the manager's transient global pause flag. Pause preserves downloaded bytes and the active reservation; resume continues through the library's cache/download machinery. A restart, invalid range response, or changed resource must never be reported as preserved progress when bytes were discarded.

Keep the network policy captured at task creation. Changing the default affects only future tasks. Preserve the existing meaning of Wi-Fi-only: an unmetered Ethernet connection is not automatically Wi-Fi, and metered Wi-Fi is not automatically forbidden. Per-task network gating must remain separate from user pause, and mixed-policy tasks must not block each other unnecessarily. Network callbacks, service startup, and scheduled recovery belong to the managed-transfer owner. Tests must prove no media bytes are requested through a disallowed network.

Declare the required foreground-service and notification integration using the supported Android APIs. Notification taps open Downloads once. Observe actual service/time-limit outcomes and reconcile unfinished transfers after relaunch; do not promise execution after user force-stop. Clean up callbacks, executors, index/cache handles, and service-owned resources through their owning lifecycle.

### Public File Publication

Use a private non-evicting transfer cache while downloading. Once the transfer is complete, publish one MP4 under `Downloads/sctv-dl` using MediaStore and a pending row. Copy from a cache-only reader with no network fallback. Mark the task completed only after the public URI is finalized and readable.

Persist the pending publication URI before copying. Reconcile process death before, during, and after publication without duplicate visible files or false completion. A publication failure retains the private completed media and exposes retry-publication. Report temporary disk-space failures honestly. Release the private transfer resource after successful publication, with retryable cleanup bookkeeping; generic cache cleanup must not touch it.

Deleting a completed file removes the owned public file and marks the task missing while preserving its record. Removing a terminal record preserves the public file. Cancelling an active attempt removes its transfer and private partial data. Destructive batch actions explain their scope and confirm it. File-operation permission requests, if required by the system for a particular URI, are owned by the Activity/UI boundary and cancellation leaves state truthful.

## Download Management and Presentation

Provide filters for all, downloading, unfinished, completed, and files removed. Paused tasks remain in the active-download family; publication failures belong to unfinished. Retain independent list positions for each filter and clear selection when the filter changes.

Support multiselect and select-all within the visible filter. Offer only supported actions: pause, resume, retry/redownload, retry publication, cancel, delete video, and remove record. Back exits selection before leaving Downloads.

Immediately before each batch mutation, re-read the task and compare its attempt identity and action eligibility. Skip stale/unsupported targets and continue after individual failures. Summarize successes, skips, and failures. UI busy state does not replace repository-level race protection.

Task cards use a real 16:9 content cover with a programme-cover fallback, title, programme/date/quality metadata, status, and appropriate actions. Do not fabricate artwork for legacy rows. Group missing files neutrally instead of presenting them as failed transfers. Completed cards show a known file size and omit transfer-only network policy. File actions use the overflow menu, while primary actions remain labelled. Large text places artwork above full-width titles and wraps actions.

## Cache Maintenance

Add a confirmed settings action that removes only persisted programme/date/content snapshots and Coil image cache entries. Preserve favourites, history, settings, download task records, private active/finalizing media, and public files.

Coordinate clearing with in-flight metadata/image work: a request started before cleanup must not silently recreate the cleared persistent snapshot. Reject stale writes using a cache generation or equivalent owner-scoped barrier. Retained accepted screen content may stay visible until the next explicit refresh; clearing cache must not cause an unsolicited accepted-data replacement. Report partial cleanup failures accurately and make the action retryable.

## Player Recovery and Controls

Treat a quality switch as an operation with previous source, position, speed, and play intention. Keep the same session. Commit the selected quality when the replacement is usable. If preparation fails, restore the previous source/context and report the failed switch. Guard asynchronous callbacks by source-operation identity. A pause, ordinary background transition, or committed navigation during switching cancels the earlier play intention and prevents rollback from restarting playback.

If both the replacement and restoration fail, retain the last usable retry context and expose an error action. Avoid repeated automatic rollback loops. Preserve delayed disposal, explicit PiP, fullscreen window restoration, and accepted content/download metadata.

Align the lower controls with Flutter's compact single-row arrangement: play/pause, elapsed time, seek track, duration, speed, quality, and fullscreen. PiP stays at the upper right. Reserve stable time/label widths, use hour-aware timestamps and tabular digits, remove unnecessary menu chevrons, and allow horizontal overflow at large text sizes instead of shrinking touch targets. A single quality can be inspected without reloading it. Preserve accessibility holds and the existing 3.5-second playing-only hide policy.

## Delivery Sequence

1. Add content identity, user persistence, safe favourites import, history/backup, and playback progress integration.
2. Implement history navigation/presentation and cache-maintenance settings.
3. Add durable download evolution, managed Media3 transfers, legacy coexistence, network recovery, and public-file publication.
4. Add download filters, batch actions, file deletion, task artwork, and storage feedback.
5. Complete player quality recovery and compact control presentation.
6. Run integration/regression verification and reconcile permanent Android documentation and instructions with the implemented contracts.

Each phase must remain testable. Do not commit phases without an explicit commit request. After completion, move reusable contracts into the owning Android documents and remove superseded design/execution checklists as required by repository guidance.

## Verification and Acceptance

Add behavioural regression tests before changing the corresponding implementation. Cover:

- Version-1 upgrade, interrupted/idempotent favourite import, restore authority, preserved legacy tasks, and backup exclusion of runtime media state.
- History completion threshold, 500-entry retention, exact online/local identity, legacy local progress, failed persistence, serialized writes, and removal/clear versus late writes.
- Resume while paused, completed replay, first visible resumed frame, pause/background/exit progress flushing, and navigation/PiP ownership.
- Mixed download network policies, durable pause, Range-capable continuation, changed-resource failure, retry identities, duplicate reservation, process recovery, and legacy jobs.
- Public-file publication interruption, retry without retransfer, storage failure, missing URI, file deletion versus record removal, and batch partial failures/stale attempts.
- Cache clearing while requests are active, protection of user/media data, and retryable partial cleanup failure.
- Quality replacement failure/rollback, rollback failure, overlapping user pause/background, stale callbacks, and disposal.
- History/download selection and search, filter scroll restoration, light/dark themes, narrow/expanded windows, keyboard interaction, 200% text, reduced motion, loading/empty/error states, fullscreen, predictive back, and explicit PiP.

Run Android formatting, `check`, debug assembly, R8 release assembly, and relevant instrumentation on an explicitly selected disposable agent-owned AVD. Use fixture MP4s and local stub servers for transfer/decoder evidence; live upstream checks use HEAD or a small Range only. Preserve the user's emulators and restore temporary settings/processes. Run repository formatting and documentation-link checks. Run Web checks/build only if shared Web/tooling behaviour changes.

Report unit/build, device, live-network, backup/restore, and physical-device evidence separately. A passing subset must not be described as complete acceptance.

## References

- [Media3 downloading media](https://developer.android.com/media/media3/exoplayer/downloading-media): managed transfers, persisted stop reasons, requirements, and service ownership.
- [Platform DownloadManager API](https://developer.android.com/reference/android/app/DownloadManager): legacy transfer capabilities and file operations.
- Existing pinned Media3 1.11.1 source artifacts are available in the local Gradle cache for implementation-level API verification.
