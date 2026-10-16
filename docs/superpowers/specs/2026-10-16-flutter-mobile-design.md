# Flutter Mobile Client Design

Status: approved implementation baseline. The user approved the product direction and written specification on 2026-10-16, requesting that the implementation plan be committed before execution. Progress and actual verification belong to the [implementation plan](../plans/2026-10-16-flutter-mobile.md).

This specification owns the Flutter client's initial product scope and acceptance criteria. Existing contracts remain in [Architecture](../../architecture.md), [Upstream API](../../upstream-api.md), and the [Android Client Design](../../android-client-design.md). The Flutter client is an additional application; the existing Web, Tauri, and Kotlin clients retain their behaviour and storage.

## Intent and Product Boundary

Build a complete Flutter mobile client for Android and iOS. It must cover the existing native client's browsing, search, favourites, broadcast archives, online playback, quality selection, batch downloads, background transfers, local playback, file actions, and settings. Include local viewing history, resume positions, and capability-dependent download pause/resume as agreed in the proposed feature set.

The application connects directly to public upstream metadata and media services. No separately deployed Node service, account, or cloud synchronization is required. All user state stays local. Real programme metadata, genuine media capabilities, and actual transfer outcomes drive the interface.

Initial product targets are Android 10/API 29 and newer, and iOS 15 and newer, on phones and tablets. These are product support floors, not claims about the minimum versions supported by the dependencies. Lowest-version devices and current stable OS versions must pass the acceptance matrix before support is claimed.

The application label remains `蜀台回看`. Use the project name `sctv_dl_mobile` and distinct Android/iOS application identifiers `dev.sctvdl.flutter` so the Flutter and Kotlin clients can coexist. A separate installation has its own data; no automatic import of browser, desktop, or Kotlin databases is implied.

Documentation, comments, test names, and future commit messages use English. Product copy and upstream programme names remain Chinese. Commit, push, deployment, signing, and store submission require the user's corresponding request.

## Approach and Dependency Decisions

Use an independent Flutter project under `flutter/`, sharing business contracts and portable JSON fixtures with the repository rather than attempting to import TypeScript or Kotlin source. Direct upstream transport avoids a mandatory server deployment. Reusing the normalized Node API remains an optional future transport, with its own deployment configuration, rather than a dependency of the mobile application.

Use one application package with feature directories and explicit repository/platform boundaries. Do not introduce a multipackage workspace, generated dependency-injection framework, or a use-case class for every repository method.

| Responsibility                  | Selected dependency or capability                                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| UI                              | Flutter Material 3, application theme tokens, platform-aware route transitions and system sheets           |
| State and dependency injection  | `flutter_riverpod`, with Notifiers and provider overrides for tests                                        |
| Navigation                      | `go_router`, retained primary branches, restorable identifier-based routes                                 |
| Metadata and media preflight    | `dio`, separate clients and cancellation scopes                                                            |
| Durable relational state        | `drift` and its supported native SQLite integration                                                        |
| Immutable state and JSON models | `freezed`, `json_serializable`, and `build_runner`                                                         |
| Player integration              | `better_player_plus`, isolated behind `PlaybackBackend`                                                    |
| Background transfers            | `background_downloader`, isolated behind `TransferGateway`                                                 |
| Covers                          | `cached_network_image`, with a configured image transport and bounded image decoding                       |
| Files and sharing               | `path_provider`, `share_plus`, and native file/document actions where a package lacks a required operation |
| Platform information            | Native build/package information and device-info adapters; no UI dependency on platform APIs               |
| Tests                           | `flutter_test`, `integration_test`, provider overrides, and local HTTP fixtures                            |

Pin a compatible stable Flutter SDK and Dart constraints during project setup, and commit the application's `pubspec.lock`. Use compatible stable package releases rather than copying version snippets from older documentation. Record native Gradle, Kotlin, Java, and Xcode requirements in `flutter/README.md` when those files exist.

The player package is the selected first integration, not evidence of verified compatibility. Its first implementation task must exercise actual Referer/User-Agent handling, both quality URLs, local files, PiP, and disposal. If a required capability is missing, repair or replace that backend behind the same port using maintained native Media3/AVPlayer APIs. Do not silently omit a first-release feature or make a deployed proxy mandatory to mask a failed native integration.

## Application Structure and Ownership

```text
flutter/
  lib/
    app/                    # Bootstrap, dependency composition, navigation, lifecycle
    design/                 # Theme roles, brand, motion, generic state presentation
    domain/
      programmes/           # Models, validation and presentation-independent policies
      downloads/            # Task models, identities, quality and filename policies
      playback/             # Sources, sessions, history and capability contracts
      settings/             # Validated preferences and repository contracts
    data/
      programmes/           # Upstream parsing, cache and repository implementations
      database/             # Drift databases, migrations and transaction boundaries
      downloads/            # Durable submission, reconciliation and finalization
      playback/             # History persistence and media-source preparation
      settings/             # Preferences and installation identity persistence
    platform/               # Player, downloader, files, system appearance and package adapters
    features/
      programmes/           # Library, favourites and archive views/controllers
      player/               # Online/local player view, controls and session host
      downloads/            # Task presentation, controls and file actions
      settings/             # Preferences and storage management views/controllers
  test/                     # Mirrors domain, data and feature ownership
  integration_test/         # Device journeys using controlled upstream/media fixtures
  android/                  # Flutter Android host, separate from root android/
  ios/                      # Flutter iOS host
```

Views render immutable state and invoke named actions. Feature controllers coordinate presentation and call repository contracts. Repositories own persistence and business consistency. Platform adapters own native handles, file access, and system callbacks. Application composition supplies concrete implementations and maps navigation requests between features.

Features must not import sibling features or concrete `data/` and `platform/` implementations. Pure domain modules have no Flutter widgets, database objects, HTTP clients, or native handles. Shared design components do not depend on feature controllers. Extract shared workflows only when multiple consumers need the same rule.

Native transfer observation, settings hydration, and foreground reconciliation belong to application lifetime. Archive requests belong to their programme/date scope. A playback session belongs to its route and PiP host. Every listener, request, database connection, and player has a visible cleanup owner.

## Navigation and Presentation

Use three primary destinations: `节目库`, `下载`, and `设置`. The library contains `全部栏目`, `我的收藏`, and `最近观看` tabs. Each tab retains its query, sort choice, and scrolling position. History rows open the corresponding content rather than an arbitrary latest broadcast.

Compact windows use bottom navigation on primary pages. Archive and playback pages have their own return action and use the full content area. Wider windows use a rail; expanded archive layouts can show library and detail panes together. Choose layouts from available width and text size, not device model. Resizing or rotating must retain selected IDs, search, scroll anchors, and playback position.

Use the existing restrained vermilion and neutral product palette, semantic theme roles, system typography with Chinese fallback, 16:9 artwork, and compact content cards. Support light, dark, and system appearance; Android dynamic colour is optional and defaults off. Hide unavailable platform appearance options on iOS.

Use at least 48 logical pixels for interactive targets. Support 200% text scaling, screen readers, system reduced motion, safe areas, cutouts, gesture navigation, and keyboard insets. Long titles remain inspectable, actions stay reachable, and decorative images do not duplicate announcements.

Theme changes preserve the active destination, focus, scroll, and player. Shared-cover motion is limited to a single selected source and destination; use an ordinary page transition when that cannot be guaranteed. Cancelled back gestures retain the current entry and live resources. System animation preferences take precedence over custom motion.

Back closes a player menu, fullscreen, archive selection, or active library search before leaving its page. Returning to a retained page does not accept pending data updates. Notification navigation is consumed once and must not override later manual navigation after recreation.

## Programme Library and Archive

Preserve the existing catalogue search, service/name ordering, favourites, and manual programme exploration. Favourite controls update immediately without moving cards in the retained all-programmes view; the startup favourite-priority snapshot remains stable for that browsing session. Favourites membership updates immediately. Exploration uses real catalogue data, changes on explicit shuffle, and has no timer, autoplay, invented ranking, or fabricated freshness information.

Cold loads show noninteractive skeletons matching the eventual layout. Cache-backed screens remain usable while checking for updates, without replacing content with a spinner. Successful changed results produce an accessible toolbar update action; accepting applies the newest compatible snapshot. Unchanged responses and timestamp changes alone do not advertise new content. Initial failures, cached-refresh failures, empty archives, empty favourites, and empty search results have distinct feedback and retry/navigation actions.

Archive pages retain the programme header, favourite action, recent broadcast shortcuts, and a month-grouped full date sheet. Only returned broadcast records are selectable. Keep a selected older date visible in the shortcut row. The selected broadcast's date ID, not date text, identifies content requests.

Recognize full episodes using the existing programme-name/date title rule, including supported parentheses and whitespace handling. Never infer a full episode from list position. Full episodes retain service order; clips sort by publication time, with a toggle for direction, stable ties, and unknown times last. Display offset-free publication timestamps in `Asia/Shanghai` and include the date when it differs from the broadcast date.

Available cards open playback from the whole card. Entries without media stay readable and explain their unavailable state. Batch mode offers whole-card checkbox selection, select all, full episodes only, selected count, and a fixed quality/download action. Programme/date changes clear incompatible selection. Sorting and accepting pending updates are disabled during selection.

The quality sheet shows meaningful variants for one item and explains per-item fallback for a mixed batch. Closing it creates no tasks. Submission reports actual accepted, duplicate, fallback, and failed results independently, with a route to Downloads.

## Upstream Boundary and Request Lifecycle

Retain the contracts in [Upstream API](../../upstream-api.md):

- Catalogue page 0, size 100; dates for a validated programme ID; contents for a returned date record ID.
- An upstream success envelope has `rs = 200` and a validated expected payload. Bound metadata bodies to 2 MiB before complete buffering.
- IDs are decimal strings. Accept numeric IDs only when they are nonnegative integers no greater than `9007199254740991`; preserve larger IDs exactly only when supplied as strings. Never normalize through floating point.
- Validate actual ISO calendar dates, keep the last upstream record for duplicate calendar dates, and sort newest first.
- `video` maps to standard; `videoStandard` maps to smooth. Normalize absent optional fields to null, deduplicate equal source URLs, and report actual-quality fallback.
- Resolve relative media against `https://fscgc.scgchc.com/` and relative artwork against `https://kscgc.sctv.com/`.
- Initial media targets must be credential-free HTTPS MP4 URLs on `fscgc.scgchc.com` or `fscgc.sctv-tf.com`, using the default port. Do not accept arbitrary user-entered URLs.
- Covers use the existing HTTPS host families `kscgc.sctv.com`, `kscgc.scgchc.com`, and `kscgc.sctv-tf.com`; unsupported covers use the fallback.
- Media probes, playback, and transfers send `Referer: https://scgc.video.play/` and an explicit `sctv-dl/<installed-version>` User-Agent. Do not attach metadata guest headers to covers or media.

Metadata uses the existing anonymous Android-compatible request profile and a persisted installation UUID. Android supplies its native Build values. Until an official iOS request profile is observed and separately adopted, iOS uses the existing fixed compatibility values (`google`, `Pixel 8`, Android `14`, `deviceType: android`), rather than claiming an observed official iOS profile. Both use upstream compatibility `appVersion: 9.6.1.5`, empty guest `userId`, `Authorization`, and `captchaId`, and the existing metadata User-Agent. The application's own version remains independent.

Create the installation UUID once before concurrent requests can use it. Exclude identity from user preference backup/export. Let the HTTP transport manage Host, connections, and supported compression; do not copy browser cookies or unrelated credentials.

Application-controlled metadata, image, preflight, and playback transports reject redirects. Verify this in the selected player/image adapters; package defaults are not evidence. Native background transfers retain the documented system-managed redirect exception, as the existing Android system downloader does. iOS background URLSession follows redirects without invoking the application's redirect delegate; do not promise the Node proxy's stricter policy for it. This exception does not weaken the Web/Node proxy or initial native URL validation.

Use keyed cancellation tokens plus request generations. Cancelling obsolete work and rejecting stale results are separate protections. A reply for one programme/date must not enter another key's state, even if it arrives after cancellation. Disposed scopes release listeners and ignore subsequent callbacks.

Configure bounded connection and metadata reception deadlines, with distinct user-facing timeout, HTTP, business, malformed-response, and storage failures. A long progressing MP4 has no metadata-sized whole-operation deadline. Media probes use HEAD, then a bounded small Range request when HEAD is unsupported, closing the response without buffering a full file.

## Persistence and Snapshot Acceptance

Use Drift for programme/date/content snapshots, favourites, preferences, viewing history, and the application's durable download index. Keep user state eligible for backup separately from reconstructible cache and runtime transfer records, using separate user/runtime database files and native backup rules. Downloaded videos, native task IDs, temporary files, and installation identity are excluded from backup.

Snapshot keys distinguish the catalogue, a programme's dates, and a programme/date's contents. Persist successful empty responses with a fetched marker; zero rows must not mean never fetched. Refresh replaces only its matching snapshot atomically. Failure retains the last successful snapshot and useful error context.

Controllers keep the accepted display snapshot distinct from the newest repository snapshot. Initial results appear immediately; later differences require explicit acceptance, including transitions to empty. Date changes invalidate pending content from the old key. Apply a changed date list before selecting/loading the matching content key. Retry and app resume do not implicitly accept updates.

Store restorable route IDs, queries, sort direction, scroll anchors, and compatible selected content IDs. Do not serialize player handles or full mutable response models into routes. Pass the accepted archive selection in memory; resolve identifiers from validated cache/upstream on process restoration.

Preferences have versioned validation and safe per-field defaults. Hydration and delayed writes cannot overwrite newer user changes. Serialize saves and surface persistence failures while retaining usable in-memory state. Runtime transfer IDs restored without their original native tasks must not become runnable jobs automatically.

Cache cleanup removes only reconstructible metadata/images. It does not cancel downloads, remove favourites/history, or delete completed videos. A separate explicit history action clears viewing records. File deletion is a separate task/file action.

## Playback and Viewing History

Use a dedicated player route for online or local playback. Pin its accepted content reference, metadata, and validated sources; pending repository updates cannot change what is being watched or downloaded from that route.

Playback starts paused with the saved quality preference and explicit fallback. Show the full title, programme, and broadcast date below the surface, followed by an online-content download action. Local playback has no download action. Short landscape windows and large text can scroll the surrounding context without hiding controls.

Controls provide play/pause, elapsed/total time, seeking, speed, actual distinct quality choices, fullscreen, and explicit PiP where the device supports it. Hide controls only during uninterrupted playback after 3.5 seconds of inactivity, respecting accessibility timing. Keep them visible while paused, buffering, focused, seeking, in error, or choosing an option. Unknown duration remains unknown.

Switch quality within the existing playback session, preserving position, speed, and intent to play. A failed switch retains or restores the previous usable source with actionable feedback. Fullscreen and PiP transitions must not create duplicate decoders or sessions.

Ordinary backgrounding pauses; explicit PiP can continue. The PiP host retains session ownership until PiP stops or restores the player route. Audio interruption, route changes, lock/unlock, and lost audio focus must not cause unintended autoplay. Restore previous orientation, system UI, and audio-session ownership when leaving the relevant mode.

Committed navigation pauses immediately and disposes only after the leave animation. A cancelled gesture does not dispose. Session IDs guard delayed initialization and cleanup so an old route cannot clear a newly opened player. Remove observers, release the native player, restore window state, and close media resources exactly once.

Viewing history is keyed by programme/date/content reference and stores accepted title/artwork context, last position, known duration, last viewed time, and completion state. Online and downloaded copies share that content identity. Persist progress at most once every five seconds while advancing, and on pause, seek completion, backgrounding, and route exit. An ended item or a position at least 95% through a known positive duration is completed. Reopening an incomplete item offers its saved position while remaining paused; replaying a completed item starts at zero. Retain the latest 500 entries and provide per-entry removal and clear history.

## Downloads and Native File Ownership

`background_downloader` owns native network transfers, resumable data, and execution scheduling. The application owns content identity, requested/actual quality, filename policy, durable task presentation, and publication/export state. Avoid a competing Dart HTTP download engine or a Dart-only queue that stops draining when suspended.

Persist a task/attempt ID, content reference, pinned source, actual quality, network policy, safe unique planned filename, and native correlation identity before enqueue. A transaction prevents duplicate active downloads of the same content and actual quality. A retry gets a new attempt ID; callbacks from an older attempt cannot modify the replacement.

Run at most two transfers concurrently using the plugin's native holding queue. Submit a batch of at most 100 distinct items with independent results. User-initiated long transfers use the plugin's supported Android UIDT or foreground-transfer configuration, including required notifications and permissions. Test older Android execution limits and long transfers; a short foreground download does not establish background support.

Subscribe before reading native task snapshots. Serialize submission/reconciliation transitions, merge buffered events with the snapshot, and reject stale-attempt/nonterminal updates after a terminal result. Reconcile plugin records, native tasks, resumable state, and actual files on startup, foreground entry, and completion callbacks. Recover an interrupted enqueue by its preallocated identity before any resubmission. Ambiguous or unverifiable tasks become interrupted with an explicit retry action rather than producing duplicate transfers.

Present these states with their actual reasons: preparing, queued, running, waiting, paused, retrying, finalizing, completed, failed, cancelled, interrupted, and missing. Byte counts come from the transfer; unknown totals use indeterminate progress. Show pause/resume only when the task confirms support. Resume failure must report a restart or failure truthfully, never append a new full response to existing bytes.

Retry HTTP/network failures only within the plugin's bounded retry policy. A manual retry revalidates the content/source and file destination. One member's failure does not discard other accepted batch members. Filename generation retains the actual quality and a unique attempt suffix, rejects path separators/reserved forms, and caps a component at 255 UTF-8 bytes without splitting code points or clobbering existing files.

`仅 Wi-Fi 下载` is a default for future tasks. Record the effective network policy in each task; changing settings does not silently replace existing work. On iOS this means disabling cellular transport, which also allows other noncellular connections; do not claim it proves an unmetered network. Request notification or other capability permissions at the action that needs them, without gating browsing.

### Android Files

Transfer into an app-owned staging area, then publish completed videos to public `Downloads/sctv-dl` through supported scoped-storage APIs. Persist the returned content URI. Do not construct a public filesystem path or request broad storage access.

Public publication is a distinct finalization step. If the process is unavailable at transfer completion, reconcile and finish publication on the next available lifecycle callback/launch. Until the destination is verified, show finalizing rather than a completed public file. Publication failure preserves the downloaded private file and exposes retry-publication without downloading the video again.

Open, share, and local playback use content URIs and temporary read grants where needed. Removing a terminal record retains the public file. An explicit delete-file action deletes only that task's owned file. Files published to Downloads remain available after application uninstall.

### iOS Files

Save completed media under `Documents/Downloads`, and enable Files visibility using the supported document-sharing configuration. Keep databases, installation state, and other private data outside Documents. Store relative base-directory references rather than absolute sandbox paths, which can change.

Provide local playback, system sharing, and explicit Save to Files export. Export cancellation leaves the local file intact and creates no false success result. Do not label the application's Documents folder as a system-wide Downloads directory. Local files disappear with app removal unless the user exported another copy.

Background URLSession owns scheduling. Normal suspension, OS process reclamation, user force-quit, and unavailable resume data have different outcomes. Reconcile on relaunch and display actual interrupted/waiting states; never promise uninterrupted transfers after user force-quit. Downloaded media is excluded from iCloud backup.

### Removal and Missing Files

Cancelling an active task cancels its native transfer and cleans only owned partial artifacts. Removing a terminal record leaves the completed video. Deleting a completed file is a separately labelled action. Recheck availability before open/share/play and during reconciliation; external removal produces a missing state with re-download. Cleanup failures remain visible rather than pretending cancellation or deletion succeeded.

## Verification and Delivery Criteria

All items below are requirements for implementation, not completed evidence.

| Area            | Required evidence                                                                                                                                                                                                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contracts       | Shared fixture parity; malformed envelopes; unsafe numeric IDs; invalid calendar dates; last-record deduplication; quality mapping/fallback; duplicate URLs; historical CDN policy; full-episode recognition; Unicode filenames                                                     |
| Cache and state | Cold/warm loads; successful empty snapshots; offline cached pages; out-of-order replies after cancellation; explicit update acceptance; stable selection/search/scroll; preference migration and failed saves                                                                       |
| Playback        | Real fixture decoding and sampled live CDN access on both OS families; custom headers; seek/source/speed retention; failed switch recovery; online/local playback; audio interruption; fullscreen/PiP restore; cancelled back and delayed disposal                                  |
| Downloads       | Real native fixture transfers; unknown length; redirect policy/exception; capability-dependent pause/resume; server ignoring Range; expired resume state; duplicate submission; partial batch failure; enqueue crash recovery; disk-full; publication/export failure; removed files |
| Background      | App suspension and relaunch; OS process reclamation; user force-quit; Wi-Fi loss/recovery; long transfer across Android execution limits; native holding queue draining without an active Dart UI                                                                                   |
| UI              | Phone/tablet, portrait/landscape, both themes, system theme, reduced motion, 200% text, keyboard focus, TalkBack/VoiceOver, loading/empty/error/offline states, native back gestures and notification routing                                                                       |
| Persistence     | Restart retains favourites/settings/history/tasks; migration preserves valid prior data; sandbox paths are resolved fresh; backup excludes native task IDs/media; cache cleanup preserves user data/files                                                                           |
| Release         | Android APK/AAB and iOS release compilation, installed release-mode smoke journeys, dependency/license inventory, actual minimum/current OS coverage, signing limitations reported separately                                                                                       |

Use disposable emulators/simulators and controlled HTTP/media fixtures for automation. Restore temporary preferences/processes and remove fixture downloads. Do not use the user's daily emulator. Native playback/PiP/background claims require device evidence; passing Dart tests or compiling an app does not establish those behaviours. Separate physical-device limitations from simulator results.

During implementation document and run, from `flutter/`, `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`, `flutter test`, `flutter build apk --release`, `flutter build appbundle --release`, and `flutter build ios --release --no-codesign`. Record actual device IDs and integration invocations in the implementation evidence rather than implying every target was tested.

Add Flutter CI for generation/format/analysis/tests and release compilation, with native runtime tests as a distinct job or documented local gate. Pin SDKs, cache portable dependencies, and keep signing credentials/local SDK paths/generated caches out of Git. Add Dart dependency updates for `/flutter` and review native transitive dependencies with their owning plugin.

Exclude Flutter native/generated products from root Web watching, TypeScript/test discovery where necessary, formatting, and lint scans. Flutter owns Dart/native formatting. Any change to shared fixtures or Web tooling requires the repository's `pnpm check` and `pnpm build`; documentation-only work requires formatting and local-link verification, without application builds.

Keep the setup guide in `flutter/README.md` once implemented. Convert durable product/architecture constraints into the owning Flutter documentation and remove obsolete execution checklists after delivery. Preserve unrelated working-tree changes; do not commit them as part of Flutter work.

## Implementation Order

1. Validate the selected player/downloader integrations with controlled native fixtures and sampled live media, including both platforms' file ownership and lifecycle boundaries. Establish the portable Flutter scaffold and contract tests as part of this deliverable.
2. Implement the validated data boundary, persistence, settings hydration, accepted snapshots, and restorable application shell.
3. Complete catalogue, favourites, archive, batch selection, player controls, and viewing history against those contracts.
4. Complete durable submission/reconciliation, background execution, publication/export, local playback, and all task controls.
5. Finish adaptive/accessibility states, release builds, CI, dependency management, and the platform acceptance matrix.

Implementation can continue through independent areas while a particular device is unavailable. Record that missing evidence explicitly, and retain full functionality in code. A skeleton, mocked download progress, a demo-only player, or an untested package feature list does not satisfy the complete-client requirement.

## Research and Environment Evidence

Reviewed on 2026-10-16:

- [Flutter architecture guidance](https://docs.flutter.dev/app-architecture/guide): views/controllers and repositories/services, with additional domain workflows where justified.
- [Riverpod providers](https://riverpod.dev/docs/concepts2/providers) and [go_router](https://pub.dev/packages/go_router): state/dependency composition and navigation.
- [Dio](https://pub.dev/packages/dio), [Drift](https://pub.dev/packages/drift), [Freezed](https://pub.dev/packages/freezed), and [json_serializable](https://pub.dev/packages/json_serializable): HTTP, durable state, and model generation.
- [Better Player Plus](https://pub.dev/packages/better_player_plus): declared custom-header, speed, resolution, and PiP capabilities; real upstream/device acceptance remains required.
- [Background Downloader](https://pub.dev/packages/background_downloader), [lifecycle](https://github.com/781flyingdutchman/background_downloader/blob/main/doc/lifecycle.md), [configuration](https://github.com/781flyingdutchman/background_downloader/blob/main/doc/CONFIG.md), [parameters](https://github.com/781flyingdutchman/background_downloader/blob/main/doc/parameters.md), and [storage](https://github.com/781flyingdutchman/background_downloader/blob/main/doc/storage.md): native queues, transfer control, foreground/UIDT execution, network policy, and platform file limitations.
- [Apple background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background): system-owned scheduling and the automatic redirect behaviour of background sessions.
- [Cached Network Image](https://pub.dev/packages/cached_network_image), [Share Plus](https://pub.dev/packages/share_plus), and [Path Provider](https://pub.dev/packages/path_provider): covers, sharing, and platform directory references.

The workstation has Flutter/Dart executables on PATH and Xcode 27.0 (`27A266a`). The initial `flutter --version --machine` invocation could not complete because the SDK attempted to update its shared cache outside the current writable sandbox. No Flutter version, dependency resolution, native build, or runtime capability is claimed from that failed command. SDK setup/permission handling belongs to the implementation environment check, not a reason to change the product scope.
