# 蜀台回看 — Flutter

The standalone Android/iOS client for browsing Sichuan TV programmes, favourites and viewing history, playing online or downloaded MP4s, and managing native background downloads. Its package is `sctv_dl_mobile`; both native hosts use `dev.sctvdl.flutter` for Release/Profile and `dev.sctvdl.flutter.debug` for Debug. The existing [Web](../README.md), [Kotlin Android](../android/README.md) and [Tauri desktop](../docs/desktop.md) clients remain separate applications.

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

Implementation ownership, product behaviour, persistence and resource lifecycles are documented in [Flutter Client Architecture](../docs/flutter.md). [AGENTS.md](AGENTS.md) owns contribution and readability rules. Features consume domain contracts; concrete composition belongs in `lib/app/`, and native effects remain in `lib/platform/`.

## Player dependency repair and licenses

[packages/better_player_plus](packages/better_player_plus) is the portable source copy of `better_player_plus` **2.0.0** originally fetched from [pub.dev](https://pub.dev/packages/better_player_plus/versions/2.0.0). The app selects it through the path override in `pubspec.yaml`. Preserve its [upstream license](packages/better_player_plus/LICENSE) and [patch provenance](packages/better_player_plus/LOCAL_PATCHES.md).

The local repairs enforce streaming redirect rejection on Android/iOS playback, explicit iOS PiP ownership, awaitable single disposal and Android content-URI handling. Rebase and review those patches when upgrading the player; replacing the path override with an unmodified hosted version removes application behavior. The patch document records the native implementations and their verification limits. Do not reformat or regenerate the upstream package as part of application-wide Dart cleanup.

Direct Dart dependencies and exact transitive versions are listed in `pubspec.yaml` and `pubspec.lock`; native dependencies are also declared by their owning plugins, including the player's Android Media3/OkHttp and iOS Swift packages. Review native dependency/license changes with that plugin rather than treating a Pub version bump as the whole update. The repository's Dependabot configuration schedules Pub updates for `/flutter`; the vendored override requires a deliberate source update.

## Development checks and release compilation

Run from this directory:

```sh
flutter pub get --enforce-lockfile
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test test_driver integration_test tool
dart run tool/check_boundaries.dart
flutter analyze --fatal-infos
flutter test
./android/gradlew -p android :better_player_plus:testDebugUnitTest --no-daemon
flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build ios --release --no-codesign
```

The formatter scopes include integration tests and deliberately exclude the vendored player's upstream Dart. After generation, inspect the diff and commit generated application sources with the source change. Use the generation command above without the obsolete `--delete-conflicting-outputs` option.

Debug builds on Android and iOS display `蜀台回看 Debug` and use the `.debug` application/bundle ID suffix, so they can coexist with Release/Profile (`蜀台回看`). Their private settings, history and download records are separate; changing the application identity does not migrate existing data. Android Kotlin namespaces and platform-channel names remain stable. iOS debug signing must target the debug Bundle ID.

Release APKs are split into `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, and `app-x86_64-release.apk`. Choose the APK matching the device architecture; modern ARM phones generally use `arm64-v8a`. Omit `--split-per-abi` when a universal APK is needed. The AAB remains a single upload artifact for store-managed device delivery. iOS builds are unchanged and do not use Android ABI splitting.

Dart tests use [shared JSON fixtures](../shared/fixtures), disposable SQLite databases and controlled HTTP services. Player/download tests with fake native boundaries verify application decisions; they do not establish native decode, background execution or OS file behavior. Use disposable emulators/simulators and real controlled media/transfer fixtures for runtime acceptance. Record each integration command, device ID, OS version and observed lifecycle mode with its result.

The [Flutter workflow](../.github/workflows/flutter.yml) pins Flutter 3.47.6. Its Ubuntu job checks generation, application Dart formatting, analysis, tests and native player HTTP-policy tests/instrumentation compilation, then compiles Android APK/AAB artifacts. Its macOS job compiles and archives an **unsigned** iOS app. Workflow source validation is distinct from an actual hosted CI run; neither release compilation nor a fake-backed test is native runtime evidence.

Android release validation currently uses the debug signing configuration in the native host. The iOS CI app is unsigned and is not an installable distribution package. Production keystores, Apple signing/provisioning, store upload and publication remain separate release work; no production signing material belongs in this repository.

## Device verification

Use an explicitly selected disposable emulator/simulator. Keep foreground fixtures separate from suspension, OS reclamation and user force-quit. Controlled transfers and native playback use these commands from `flutter/`:

```sh
flutter test integration_test/downloads_test.dart -d <device-id>
flutter test integration_test/download_notice_test.dart -d <device-id>
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/update_notice_test.dart -d <device-id>
flutter test integration_test/playback_test.dart -d <device-id> \
  --dart-define-from-file=<fixture-defines.json>
ANDROID_SERIAL=<disposable-android-id> ./android/gradlew -p android \
  :app:connectedDebugAndroidTest --no-daemon
```

The playback fixture defines file supplies `PLAYBACK_FIXTURE_BASE64` with a small generated H264 MP4. Keep fixtures, device IDs, screenshots and run output outside tracked documentation. Native file ownership and background scheduling rules are in [Flutter Client Architecture](../docs/flutter.md#native-transfers-and-files).

For opt-in live UI verification with reviewable screenshots:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/application_test.dart -d <device-id> \
  --dart-define=LIVE_APPLICATION_SMOKE=true
```

This journey writes screenshots into ignored `build/qa/` and creates no live download. Its final `downloads-fixture-*` and `downloads-completed-*` screenshots use presentation-only task data; they establish card layout rather than native transfer or file availability. Use the controlled fixture commands above for native transfer and file behaviour.

For controlled native player interaction checks, pass a generated local H264 MP4 as base64 in a temporary JSON file with a `PLAYBACK_FIXTURE_BASE64` key:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/player_controls_test.dart -d <disposable-device-id> \
  --dart-define-from-file=<fixture-defines.json>
```

This exercises native paused playback, seeking, speed, replay, fullscreen rotation and exact surface restoration, and captures light/dark screenshots. The optional `VERIFY_ANDROID_PIP=true` define also enters native PiP and waits for the host to restore the same Activity after the `PLAYER_PARITY_PIP_READY` log marker. For a Debug Android run, use `adb -s <disposable-device-id> shell am start -n dev.sctvdl.flutter.debug/dev.sctvdl.flutter.MainActivity` for that restore; Release/Profile uses `dev.sctvdl.flutter` as the package ID. Keep fixture files and outputs outside tracked source.

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

The opt-in profile journey uses the production application, warms both cover sources, then drives uniform route progress and reports build/raster timings. It does not inject real Android gestures or establish physical-device frame pacing. The OS-gesture runner requires gesture navigation, `flutter` on PATH, and `adb` on PATH or an Android SDK environment variable. Use `python3 tool/verify_predictive_back.py --device <disposable-emulator-id>` separately to verify actual OS gesture delivery, cancellation and completion.

The launcher uses an application-owned geometric TV/play mark. On macOS, regenerate its native bitmap sizes with `swift tool/generate_icons.swift`; Android adaptive/monochrome vectors live in the native resource directory. Both Android layers share `app_icon_launcher_foreground.xml`, whose 12.5% inset scales the already-padded mark to 75% for visual parity with the Kotlin launcher icon.

## Release acceptance

Builds and controlled fixtures do not establish all platform behaviour. Before advertising a release, verify:

- Minimum/current OS versions and physical phones/tablets, including TalkBack/VoiceOver, 200% text, reduced motion and keyboard navigation.
- Physical PiP, audio interruptions, headphone/Bluetooth route loss, lock/unlock, fullscreen and correct window restoration. A simulator that reports PiP unavailable must skip that capability explicitly.
- Long background transfers, Wi-Fi/network transitions, suspension/relaunch, process reclamation and user force-quit. iOS does not promise uninterrupted downloads after force-quit.
- Interactive sharing/export cancellation, temporary URI grants, uninstall retention, actual backup/restore and a complete installed release-mode download/local-playback journey.
- Production signing, Apple provisioning, store requirements and the results of an actual hosted CI run. Debug-signed Android and unsigned iOS builds are validation artifacts, not public releases.
