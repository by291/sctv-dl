# 蜀台回看 — Flutter

The standalone Android/iOS client for browsing Sichuan TV programmes, favourites and viewing history, playing online or downloaded MP4s, and managing native background downloads. Its package is `sctv_dl_mobile`; both native hosts use `dev.sctvdl.flutter`. The existing [Web](../README.md), [Kotlin Android](../android/README.md) and [Tauri desktop](../docs/desktop.md) clients remain separate applications.

## Setup

Use **Flutter stable 3.47.6 / Dart 3.13.5**. Dependency constraints and the portable lockfile live in [pubspec.yaml](pubspec.yaml) and [pubspec.lock](pubspec.lock). Keep SDK paths, native signing identities and generated caches outside tracked source.

- Android: Android 10/API 29 or newer; Java 21 for Gradle, Android SDK platform/build tools 36, and NDK `28.2.13676358`. The checked-in wrapper uses Gradle 9.3.1 and Android Gradle Plugin 9.1.0. Java/Kotlin output targets Java 17.
- iOS: iOS 15 or newer; macOS with Xcode, its command-line tools and iOS SDK. Flutter manages Swift package/plugin integration; install CocoaPods when required by a plugin. A physical-device installation needs your development team and signing configuration.

From this directory:

```sh
flutter --version
flutter doctor -v
flutter pub get
dart run build_runner build
flutter devices
flutter run -d <device-id>
```

Accept Android SDK licenses when `flutter doctor` requests them. Use the native tools' normal local SDK configuration; do not commit `android/local.properties`, Xcode user settings, provisioning profiles or keystores.

The application connects directly to the anonymous upstream API; it does not require a running Web/Node proxy. See the [upstream contract](../docs/upstream-api.md) for endpoint, ID, quality and media URL rules. Browsing does not require notification or storage permission. Request transfer/file capabilities when an action needs them.

## Source ownership

| Location                       | Responsibility                                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------------------------------- |
| [lib/app](lib/app)             | Bootstrap, dependency composition, providers, routing and application lifetime                          |
| [lib/domain](lib/domain)       | Immutable models, programme/media/filename policies and repository/native contracts                     |
| [lib/data](lib/data)           | Bounded Dio metadata requests, Drift persistence, settings, history and durable download reconciliation |
| [lib/platform](lib/platform)   | Native playback, background transfers, file publication/export/sharing and strict cover transport       |
| [lib/features](lib/features)   | Programme library/archive, selection, playback, downloads and settings presentation/controllers         |
| [lib/design](lib/design)       | Shared theme, artwork and state presentation                                                            |
| [test](test)                   | Domain, HTTP/SQLite fixture, controller, widget and platform-boundary tests                             |
| [android](android), [ios](ios) | Flutter native hosts, permissions, backup rules and platform integration                                |

Features consume domain contracts. Application composition owns repository/native lifetimes and supplies concrete adapters. Keep platform handles out of routes and persisted models; pin accepted programme metadata for active playback/download actions. Agent conventions are in [AGENTS.md](AGENTS.md); the [approved design](../docs/superpowers/specs/2026-10-16-flutter-mobile-design.md) defines the complete product and acceptance requirements.

User preferences, favourites and the latest 500 viewing entries belong to a user database. Reconstructible programme snapshots, installation identity and native transfer records belong to a separate runtime database, outside user backup. Successful empty snapshots retain their fetched marker. Cache cleanup preserves user data, active downloads and completed videos.

Background refresh compares parsed model fields rather than serialized JSON: programme ID/name/cover, broadcast ID/date, and content ID/title/cover/video variants/publication time. Missing optional values, JSON key order and unused metadata do not create revisions. Additions, removals and effective display-order changes do; broadcast dates retain their existing deduplication and descending-date normalization. Unchanged snapshots keep their revision while advancing the fetched timestamp. A valid refresh repairs malformed cached items. Cancellation, stale-response rejection and serialized cache writes remain authoritative.

Metadata requests use a persisted installation UUID and the Android-compatible guest profile. Android supplies native device build values; iOS uses the explicitly documented compatibility profile. Covers, player requests and transfers use separate transports and receive no metadata identity headers. Media requests use the allowed HTTPS MP4 CDNs, the required Referer and `sctv-dl/<installed-version>` User-Agent.

## Presentation

The Flutter client uses neutral surfaces with its own soft blue accents, pale blue action surfaces and light blue launcher icon, distinct from the Kotlin Android client's vermilion palette. The default light and dark themes use coordinated blue roles; the optional system dynamic-colour preference still follows the device wallpaper. Programme cards place the independent favourite action over 16:9 artwork and reserve the full lower row for the title. Grid height measures actual title layout with the current font, locale and text scaling, including CJK fallback metrics; it uses the full catalogue so filtering does not resize rows. Exploration uses a lightly tilted framed cover and a distinct primary action. The archive keeps its cover and title side by side on compact phones, switching to a text-first header at large text sizes.

Primary navigation contains Programme Library, Downloads and Settings. A heart icon beside the sort action filters only the catalogue list. Toggling it retains the exploration card, current search and ordering in the same scroll view; an empty result is shown beneath the toolbar without replacing the page. The toolbar history action opens a separate page above the navigation shell, retaining its search and scroll position across visits and passing the exact saved entry to playback.

Pending library/archive data appears as a compact, rounded blue notice anchored to the list entrance: below the library count/sort toolbar and at the archive content list after its date/count information. It follows that entrance during scrolling and is clipped to the page viewport, rather than using a fixed offset over programme headers. The refresh icon and “发现新内容” form one action with a 48-pixel minimum touch target. Its 160 ms fade/short slide respects reduced motion and never changes the scroll viewport. Accepting data does not force the library to the top; ordinary scroll clamping still applies if the updated list becomes shorter. The notice belongs to its route, is hidden on inactive retained tabs and during archive batch selection, and disappears after acceptance.

Primary destinations use a 20 logical-pixel directional slide and a 200 ms blend while retaining their navigators and scroll state. Favourite filtering transitions only the lazy catalogue region over 140 ms; the heart and search title/input use 120 ms feedback. Exploration swaps its title/artwork over 160 ms with reserved title space, keeping actions fixed. Interrupted transitions continue from the current blend and position, retain an opaque backing and exclude outgoing content from interaction, accessibility and Hero discovery. [sliver_tools](https://pub.dev/packages/sliver_tools) supplies sliver stacking while retaining viewport-only grid construction.

Opening an archive uses a 300 ms route transition and a shared cover from the selected catalogue or exploration source, including its rotation, frame and corners. Android entry, ordinary return and predictive back coordinate both pages on one route timeline: outgoing content fades during the first 35% and incoming content appears during the remaining 65%, using the Kotlin client's easing control points. Flutter's delegated transition animates the retained library together with its navigation bar; a stationary, opaque theme surface covers the fade-through gap and translated edges. Both pages keep their original layout and move at most 30 logical pixels horizontally. The right-edge gesture mirrors the direction. History, online playback and local playback reuse this page transition, including the previous page's complementary fade and opaque backing. Video textures remain live during the transition rather than using route snapshots; returning retains the archive layout and scroll position.

Archive content cards share their artwork with the fixed playback surface. Accepted playback input builds that surface on the first route frame, avoiding a skeleton-to-player layout swap. The artwork remains above the live texture until both route entry and the native first-frame signal complete, then fades out over 120 ms. Native preparation starts at the requested resume position; it does not reveal the opening frame before seeking. Metadata initialization alone never removes the artwork. Android return-cover opacity complements the departing video's fade on the same route clock, independently of rectangle easing. The current video stays mounted underneath; cancellation retains its session, position and play state. A clipped card cover does not participate in a flight or scroll itself into view; the page transition and fixed poster remain. Missing artwork uses the existing theme fallback. Reduced motion disables cover flights and the reveal fade.

Timed cover/page movement uses FastOutSlowIn; Android dragging maps system progress directly to geometry without a second easing curve. The shared cover remains in the navigation overlay throughout both fade phases. Cancellation reverses the current timeline, while completion continues from the release value without restarting. An early return during entry reverses that partial entry rather than switching opacity profiles. iOS retains Cupertino edge-back handling. The archive header is available on the first frame and stays in place while dates load or fail; a cover clipped by archive scrolling does not participate in return flight. Returning preserves library scroll and search state; replacing the archive updates the current route's programme. An asynchronous route push that interrupts a gesture restores the retained archive before it is revealed again. System gesture observation is route-owned so another delegated transition cannot unregister an active drag. Removing the archive during dragging or settlement releases the retained navigator's gesture lock. Image loading has no independent long fade. Reduced motion suppresses visual transitions while retaining both platforms' back gestures, including diagonal Android gestures. Batch selection consumes back to exit selection before allowing route navigation.

Recent broadcast shortcuts display month/day and weekday. The full date chooser remains beside the section heading. Its fixed heading sits above a bounded, lazy list of rounded month groups, with weekdays and a blue selected row. Opening directly reveals the selected date without a later scroll correction; short lists shrink to their content. Choosing an older date keeps its shortcut visible, including after window or text-size changes, without moving the archive vertically. The player uses a dark control palette with readable foregrounds and highlighted selected options. Theme changes retain the existing navigation, selection and playback lifetimes.

Player interaction follows the Kotlin client: tapping the video toggles controls during uninterrupted playback, with a 3.5-second idle timeout. Pause, buffering, errors, accessibility, keyboard focus, seeking and open menus keep controls visible; each hold has independent ownership. Play/pause, elapsed time, the seek track, duration, speed, quality and fullscreen share one compact bottom row; PiP remains at the top right. Speed and quality labels have no dropdown chevrons. Their slots reserve candidate label widths from the first loading frame; replacing the quality placeholder with metadata does not move adjacent actions. Time, speed and quality share the same label typography. Both time slots reserve the total duration's digit count, use tabular figures, and include spare horizontal room and explicit separation from the seek track. Durations of an hour or more use h:mm:ss; the track takes the remaining width without changing as elapsed digits advance. Large text or constrained viewports can scroll horizontally to preserve a usable seek target. All player buttons share white press/hover/focus feedback and rounded corners, with transparent Material surfaces above the video so ink feedback remains visible. Speed choices are 0.75×, 1×, 1.25×, 1.5× and 2×; selecting one preserves the button's width. Menus open above their control and scroll within the video height. A single available quality also opens the menu to show the current selection; selecting it again does not reload playback.

Download result notices belong to their archive/player route, expire automatically, and are removed before navigating to downloads. Returning from the source route cannot leave a notice with a disposed callback on another tab.

Retained navigation branches release shared-cover placeholders when a shortcut replaces the detail/player stack with another tab. Returning to the library restores its artwork without rebuilding its list or resetting scroll position.

Fullscreen requests both landscape orientations and hides system bars; back first exits fullscreen and restores the OS orientation policy. The same video surface/session and details scroll controller survive these layout changes. PiP displays only the video, suppresses fullscreen back interception, and retains the session until PiP exits. Error recovery remains inside the video, including fullscreen. Explicit retry preserves the last usable position, speed, source and play/pause intent, unless backgrounding or committed navigation intervenes. Playing a completed video seeks to zero; opening a video still starts paused.

Downloads keep a stable page header across loading, empty and failure states, and group tasks into active, unfinished, completed and removed-file sections. Task cards pair a 16:9 content cover (falling back to the programme cover) with the title and programme/date/quality metadata, keep file actions in the upper-right menu, and pair status with icon-and-text actions without a filled background in the footer. Large text places artwork above the full-width title. Removed files retain their records in a neutral section with redownload/remove-record actions rather than appearing as failed transfers. Completed cards show file size beside their status and omit transfer-only network policy. Active transfers retain progress, byte totals and network policy; actions and footer content wrap at large text sizes without inventing sizes or transfer speeds. State filters retain separate list positions. Batch management selects only the current filtered list, clears selection when filters change, and offers capability-aware pause, resume, retry, publication retry, cancellation, file deletion and record removal. Destructive batch actions confirm their scope; file deletion retains records and record removal retains existing files. Each operation rechecks the current attempt and state, skips stale targets and reports partial failures without stopping the remaining tasks. Settings use aligned groups and scrollable selection sheets above the root navigation. History cards show accepted artwork, exact resume positions and known-duration progress; filtering has its own recoverable empty state, and failed removal leaves playback available.

## Player dependency repair and licenses

[packages/better_player_plus](packages/better_player_plus) is the portable source copy of `better_player_plus` **2.0.0** originally fetched from [pub.dev](https://pub.dev/packages/better_player_plus/versions/2.0.0). The app selects it through the path override in `pubspec.yaml`. Preserve its [upstream license](packages/better_player_plus/LICENSE) and [patch provenance](packages/better_player_plus/LOCAL_PATCHES.md).

The local repairs enforce streaming redirect rejection on Android/iOS playback, explicit iOS PiP ownership, awaitable single disposal and Android content-URI handling. Rebase and review those patches when upgrading the player; replacing the path override with an unmodified hosted version removes application behavior. The patch document records the native implementations and their verification limits. Do not reformat or regenerate the upstream package as part of application-wide Dart cleanup.

Direct Dart dependencies and exact transitive versions are listed in `pubspec.yaml` and `pubspec.lock`; native dependencies are also declared by their owning plugins, including the player's Android Media3/OkHttp and iOS Swift packages. Review native dependency/license changes with that plugin rather than treating a Pub version bump as the whole update. The repository's Dependabot configuration schedules Pub updates for `/flutter`; the vendored override requires a deliberate source update.

## Development checks and release compilation

Run from this directory:

```sh
flutter pub get --enforce-lockfile
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test test_driver
flutter analyze --fatal-infos
flutter test
./android/gradlew -p android :better_player_plus:testDebugUnitTest --no-daemon
flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build ios --release --no-codesign
```

When `integration_test/` is present, also run `dart format --output=none --set-exit-if-changed integration_test`. The formatter scopes deliberately exclude the vendored player's upstream Dart. After generation, inspect the diff and commit generated application sources with the source change. The old `build_runner --delete-conflicting-outputs` option is no longer needed by the resolved generator version.

Release APKs are split into `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, and `app-x86_64-release.apk`. Choose the APK matching the device architecture; modern ARM phones generally use `arm64-v8a`. Omit `--split-per-abi` when a universal APK is needed. The AAB remains a single upload artifact for store-managed device delivery. iOS builds are unchanged and do not use Android ABI splitting.

Dart tests use [shared JSON fixtures](../shared/fixtures), disposable SQLite databases and controlled HTTP services. Player/download tests with fake native boundaries verify application decisions; they do not establish native decode, background execution or OS file behavior. Use disposable emulators/simulators and real controlled media/transfer fixtures for runtime acceptance. Record each integration command, device ID, OS version and observed lifecycle mode with its result.

The [Flutter workflow](../.github/workflows/flutter.yml) pins Flutter 3.47.6. Its Ubuntu job checks generation, application Dart formatting, analysis, tests and native player HTTP-policy tests/instrumentation compilation, then compiles Android APK/AAB artifacts. Its macOS job compiles and archives an **unsigned** iOS app. Workflow source validation is distinct from an actual hosted CI run; neither release compilation nor a fake-backed test is native runtime evidence.

Android release validation currently uses the debug signing configuration in the native host. The iOS CI app is unsigned and is not an installable distribution package. Production keystores, Apple signing/provisioning, store upload and publication remain separate release work; no production signing material belongs in this repository.

## Platform behavior and remaining runtime acceptance

Android transfers stage in app-owned storage and publish through scoped-storage APIs into public `Downloads/sctv-dl`. Publication is a separate finalization step: a private completed transfer remains recoverable if publication fails. Removing a terminal task keeps its completed file; deleting a file is a separate explicit action. Published public files can remain after uninstall.

iOS media lives under the application's `Documents/Downloads`, with Files visibility, local playback, sharing and explicit Save to Files export. References are relative to the current sandbox. Cancelling export keeps the local file. This application-owned folder is not the system-wide Downloads directory; unexported files disappear on app removal. Videos, runtime task state and installation identity are excluded from backup.

Native holding queues schedule at most two transfers independently of the Dart UI. `仅 Wi-Fi 下载` sets the policy for new tasks; it does not rewrite existing transfers. On iOS this disables cellular transport and can permit other noncellular connections. Native background transfers retain the documented system-managed redirect exception; application metadata, artwork and playback transports reject redirects.

The dated [Flutter Validation record](../docs/flutter-validation.md) owns exact checks, devices, native fixture results and pending acceptance. Both OS families have passed controlled playback/download fixtures and the production-composition live page journey. Android also has native pending-publication and one-shot notification regressions. Those results do not establish sustained background execution, physical PiP/audio behavior, minimum-OS support or store distribution.

For opt-in live UI verification with reviewable screenshots:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/application_test.dart -d <device-id> \
  --dart-define=LIVE_APPLICATION_SMOKE=true
```

This journey writes screenshots into ignored `build/qa/` and creates no live download. Its final `downloads-fixture-*` and `downloads-completed-*` screenshots use presentation-only task data; they establish card layout rather than native transfer or file availability. Controlled transfer/player commands and their evidence are in the validation record. Use disposable devices and keep foreground fixtures distinct from suspension, OS reclamation and user force-quit.

For controlled native player interaction checks, pass a generated local H264 MP4 as base64 in a temporary JSON file with a `PLAYBACK_FIXTURE_BASE64` key:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/player_controls_test.dart -d <disposable-device-id> \
  --dart-define-from-file=<fixture-defines.json>
```

This exercises native paused playback, seeking, speed, replay, fullscreen rotation and exact surface restoration, and captures light/dark screenshots. The optional `VERIFY_ANDROID_PIP=true` define also enters native PiP and waits for the host to restore the same Activity after the `PLAYER_PARITY_PIP_READY` log marker. On the owned Android runtime, use `adb -s <disposable-device-id> shell am start -n dev.sctvdl.flutter/.MainActivity` for that restore. Keep fixture files and outputs outside tracked source.

For resume-frame validation, use `integration_test/resume_frame_test.dart` with
the same define mechanism and a 30-second H264 fixture: solid red for the first
10 seconds, solid green thereafter. It resumes at 12 seconds, samples actual
Android texture pixels during entry to reject opening-frame leakage, and checks
the retained green frame, session and bounds after cancelling a route gesture.
It also completes a return and checks the original artwork bounds. Route progress
is driven by the test; the system-input journey below validates OS gestures.

For native catalogue typography checks, including CJK fallback fonts, scrolling, both themes and 100%/130%/200% text scaling:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/catalogue_layout_test.dart -d <disposable-device-id>
```

This uses presentation-only catalogue fixtures with placeholder artwork and writes screenshots under `build/qa/catalogue-*`. Widget tests separately cover narrow/wide layouts and custom title sizes.

For real Android edge gestures on playback and history (cancel and commit from both sides):

```sh
python3 tool/verify_predictive_back.py --device <disposable-emulator-id> --pages
```

This opt-in journey uses live metadata and paused native video, waits for the first frame before checking the revealed surface, and verifies retained geometry and scroll state. Without `--pages`, the driver checks the original catalogue/exploration/archive cases.

For warmed shared-cover rendering measurements, separate from OS input delivery:

```sh
flutter drive --profile --no-dds --driver=test_driver/integration_test.dart \
  --target=integration_test/archive_motion_profile_test.dart -d <device-id> \
  --dart-define=ARCHIVE_MOTION_PROFILE=true
```

The opt-in profile journey uses the production application, warms both cover sources, then drives uniform route progress and reports build/raster timings. It does not inject real Android gestures or establish physical-device frame pacing. Use `python3 tool/verify_predictive_back.py --device <disposable-emulator-id>` separately to verify actual OS gesture delivery, cancellation and completion.

The launcher uses an application-owned geometric TV/play mark. On macOS, regenerate its native bitmap sizes with `swift tool/generate_icons.swift`; Android adaptive/monochrome vectors live in the native resource directory.
