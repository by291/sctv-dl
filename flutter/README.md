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

Metadata requests use a persisted installation UUID and the Android-compatible guest profile. Android supplies native device build values; iOS uses the explicitly documented compatibility profile. Covers, player requests and transfers use separate transports and receive no metadata identity headers. Media requests use the allowed HTTPS MP4 CDNs, the required Referer and `sctv-dl/<installed-version>` User-Agent.

## Presentation

The Flutter client uses neutral surfaces with its own soft blue accents, pale blue action surfaces and light blue launcher icon, distinct from the Kotlin Android client's vermilion palette. The default light and dark themes use coordinated blue roles; the optional system dynamic-colour preference still follows the device wallpaper. Programme cards place the independent favourite action over 16:9 artwork and reserve the full lower row for the title. Exploration uses a lightly tilted framed cover and a distinct primary action. The archive keeps its cover and title side by side on compact phones, switching to a text-first header at large text sizes.

Primary navigation contains Programme Library, Downloads and Settings. A heart icon beside the sort action filters only the catalogue list. Toggling it retains the exploration card, current search and ordering in the same scroll view; an empty result is shown beneath the toolbar without replacing the page. The toolbar history action opens a separate page above the navigation shell, retaining its search and scroll position across visits and passing the exact saved entry to playback.

Primary destinations use a 20 logical-pixel directional slide and a 200 ms blend while retaining their navigators and scroll state. Favourite filtering transitions only the lazy catalogue region over 140 ms; the heart and search title/input use 120 ms feedback. Exploration swaps its title/artwork over 160 ms with reserved title space, keeping actions fixed. Interrupted transitions continue from the current blend and position, retain an opaque backing and exclude outgoing content from interaction, accessibility and Hero discovery. [sliver_tools](https://pub.dev/packages/sliver_tools) supplies sliver stacking while retaining viewport-only grid construction.

Opening an archive uses a 300 ms route transition and a shared cover from the selected catalogue or exploration source, including its rotation, frame and corners. Android entry, ordinary return and predictive back coordinate both pages on one route timeline: outgoing content fades during the first 35% and incoming content appears during the remaining 65%, using the Kotlin client's easing control points. Flutter's delegated transition animates the retained library together with its navigation bar; a stationary, opaque theme surface covers the fade-through gap and translated edges. Both pages keep their original layout and move at most 30 logical pixels horizontally. The right-edge gesture mirrors the direction.

Timed cover/page movement uses FastOutSlowIn; Android dragging maps system progress directly to geometry without a second easing curve. The shared cover remains in the navigation overlay throughout both fade phases. Cancellation reverses the current timeline, while completion continues from the release value without restarting. An early return during entry reverses that partial entry rather than switching opacity profiles. iOS retains Cupertino edge-back handling. The archive header is available on the first frame and stays in place while dates load or fail; a cover clipped by archive scrolling does not participate in return flight. Returning preserves library scroll and search state; replacing the archive updates the current route's programme. An asynchronous route push that interrupts a gesture restores the retained archive before it is revealed again. Removing the archive during dragging or settlement releases the retained navigator's gesture lock. Image loading has no independent long fade. Reduced motion suppresses visual transitions while retaining both platforms' back gestures, including diagonal Android gestures. Batch selection consumes back to exit selection before allowing route navigation.

Recent broadcast shortcuts display month/day and weekday. The full date chooser remains beside the section heading; choosing an older date keeps its shortcut visible, including after window or text-size changes, without moving the archive vertically. The player uses a dark control palette with readable foregrounds and explicit selected-option marks. Theme changes retain the existing navigation, selection and playback lifetimes.

Downloads keep a stable page header across loading, empty and failure states, and group tasks into active, unfinished and completed sections. Task cards distinguish status, metadata, byte progress and available actions without inventing sizes or transfer speeds. Settings use aligned groups and scrollable selection sheets above the root navigation. History cards show accepted artwork, exact resume positions and known-duration progress; filtering has its own recoverable empty state, and failed removal leaves playback available.

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
flutter build apk --release
flutter build appbundle --release
flutter build ios --release --no-codesign
```

When `integration_test/` is present, also run `dart format --output=none --set-exit-if-changed integration_test`. The formatter scopes deliberately exclude the vendored player's upstream Dart. After generation, inspect the diff and commit generated application sources with the source change. The old `build_runner --delete-conflicting-outputs` option is no longer needed by the resolved generator version.

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

For warmed shared-cover rendering measurements, separate from OS input delivery:

```sh
flutter drive --profile --no-dds --driver=test_driver/integration_test.dart \
  --target=integration_test/archive_motion_profile_test.dart -d <device-id> \
  --dart-define=ARCHIVE_MOTION_PROFILE=true
```

The opt-in profile journey uses the production application, warms both cover sources, then drives uniform route progress and reports build/raster timings. It does not inject real Android gestures or establish physical-device frame pacing. Use `python3 tool/verify_predictive_back.py --device <disposable-emulator-id>` separately to verify actual OS gesture delivery, cancellation and completion.

The launcher uses an application-owned geometric TV/play mark. On macOS, regenerate its native bitmap sizes with `swift tool/generate_icons.swift`; Android adaptive/monochrome vectors live in the native resource directory.
