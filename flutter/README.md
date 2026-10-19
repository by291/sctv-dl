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

## Player dependency and licenses

The app uses hosted Pub releases of [`video_player`](https://pub.dev/packages/video_player), [`pip_kit`](https://pub.dev/packages/pip_kit), [`audio_session`](https://pub.dev/packages/audio_session), and [`wakelock_plus`](https://pub.dev/packages/wakelock_plus). There is no Git player dependency, vendored player source, dependency override, or patch to a shared package cache. Exact versions are tracked in `pubspec.lock`; native dependencies and licenses belong to their plugins.

`VideoPlayerController` owns decoding. Application controls, gestures, route transitions, history, quality selection and aspect fitting remain application-owned. Resume and paused quality changes initialize the new controller, seek through the public API, and then attach its view without requiring a play/pause workaround. A quality change releases the old decoder before allocating its replacement and restores position, speed and user play intent, including when the previous source was buffering. Failed replacements attempt to restore the previous source.

`pip_kit`'s exported `PipPlatform` API supplies native PiP configuration, entry, exit and media actions. Android reports the authoritative Activity PiP callback on an application-owned channel; it never injects messages into a plugin's channel. `PlaybackPipHost` covers the still-mounted app with the same controller's texture while Android PiP is active. iOS uses `VideoViewType.platformView` so AVKit can use the existing AVPlayerLayer. PiP entry is explicit, never automatic. Its lifetime and system play/pause actions remain tied to the original session. Android Activity stop pauses audio when the system PiP window is dismissed.

`audio_session` owns exclusive audio focus and interruption/noisy-route subscriptions. On Android, the player disables its competing focus manager through the public mixing option; iOS retains exclusive configuration throughout initialization. The adapter applies exclusive movie-playback configuration and serializes focus transfer between sessions. Interruptions and headphone/Bluetooth route loss pause playback without automatic recovery; activation failure is reported. `wakelock_plus` holds the display awake only for foreground playback outside PiP.

Initialization has a 30-second application deadline. Disposing a session cancels its readiness wait and joins the original native release, including repeated disposal. A five-second cleanup deadline reports stalled releases, but is **not** evidence that resources were freed: the backend blocks new allocations until the original release actually succeeds. An upstream allocation failure can leave `video_player`'s creation completer pending; public APIs cannot repair that state, and a permanently unresolved/failed release requires restarting the application.

### Historical override differences

The baseline is the complete vendored `better_player_plus` override recorded before commit `75e6411`, not only the later Git pin for paused quality changes. Feasible UI, playback intent, interruption, local URI, aspect-fit, explicit PiP and lifecycle behavior has been rebuilt above. These native guarantees cannot be reproduced by the selected public APIs:

| Previous behavior                                                                                | Current limitation                                                                                                                                                                                                        |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Android 30-second/24 MiB sample-buffer loading threshold; iOS forward-buffer duration preference | `video_player` exposes no forward-duration or byte-budget setting. `backBufferDurationMs` covers already-played media and is not a replacement. Native defaults apply.                                                    |
| Reject every HTTP/HTTPS redirect and enforce native connection/read deadlines                    | Headers and URL validation are supported; redirect and network-timeout policy are not configurable. A preflight check would not constrain the player's actual transport.                                                  |
| iOS non-caching, cancellable resource loader with at most 1 MiB per Range request                | No public AVAssetResourceLoader injection exists. AVFoundation owns buffering, requests and cancellation.                                                                                                                 |
| Native first-frame readiness and initial preparation directly at the resume position             | Public initialization and seeking preserve the final position, but expose neither first-frame readiness nor an initial-position constructor. Exact first-frame timing/content cannot be guaranteed.                       |
| Disable transformed-video composition on iOS simulators                                          | The official AVFoundation plugin has no public switch. Normal non-rotated MP4s avoid this path; rotated fixtures need separate acceptance. This workaround was already in hosted Better Player, not a project-only patch. |
| Unconditional completion of pending native initialization/disposal                               | Application waits are cancellable and bounded; native allocation/release failure cannot be force-repaired through public APIs. Unconfirmed release blocks another decoder.                                                |

Commit `75e6411` had already relaxed the byte budget, strict redirect policy and exact first-frame guarantee. This migration additionally removes the hosted Better Player 10–30-second buffer preference. Keep the low-memory runtime check below: passing a fixture is evidence for that media/device, not an enforceable memory budget for every bitrate. Physical-device interruptions, route loss and PiP acceptance remain separate from fake-boundary tests and simulator checks.

## Development checks and release compilation

Run from this directory:

```sh
flutter pub get --enforce-lockfile
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test test_driver integration_test tool
dart run tool/check_boundaries.dart
flutter analyze --fatal-infos
flutter test
flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build ios --release --no-codesign
```

The formatter scopes include integration tests. After generation, inspect the diff and commit generated application sources with the source change. Use the generation command above without the obsolete `--delete-conflicting-outputs` option.

Debug builds on Android and iOS display `蜀台回看 Debug` and use the `.debug` application/bundle ID suffix, so they can coexist with Release/Profile (`蜀台回看`). Their private settings, history and download records are separate; changing the application identity does not migrate existing data. Android Kotlin namespaces and platform-channel names remain stable. iOS debug signing must target the debug Bundle ID.

Release APKs are split into `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, and `app-x86_64-release.apk`. Choose the APK matching the device architecture; modern ARM phones generally use `arm64-v8a`. Omit `--split-per-abi` when a universal APK is needed. The AAB remains a single upload artifact for store-managed device delivery. iOS builds are unchanged and do not use Android ABI splitting.

Dart tests use [shared JSON fixtures](../shared/fixtures), disposable SQLite databases and controlled HTTP services. Player/download tests with fake native boundaries verify application decisions; they do not establish native decode, background execution or OS file behavior. Use disposable emulators/simulators and real controlled media/transfer fixtures for runtime acceptance. Record each integration command, device ID, OS version and observed lifecycle mode with its result.

The [Flutter workflow](../.github/workflows/flutter.yml) pins Flutter 3.47.6. Its Ubuntu job checks generation, application Dart formatting, analysis, tests and native host instrumentation compilation, then compiles Android APK/AAB artifacts. Its macOS job compiles and archives an **unsigned** iOS app. Workflow source validation is distinct from an actual hosted CI run; neither release compilation nor a fake-backed test is native runtime evidence.

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

This exercises native paused playback, seeking, speed, replay, fullscreen rotation and exact surface restoration, and captures light/dark screenshots. The optional `VERIFY_PIP=true` define also checks native PiP (`VERIFY_ANDROID_PIP` remains an alias). Android waits for the host to restore the same Activity after the `PLAYER_PARITY_PIP_READY` log marker; iOS requests exit through the public plugin API. The standalone `playback_test.dart` checks native PiP entry/exit on either platform and explicitly skips runtimes that report it unavailable. For a Debug Android run, use `adb -s <disposable-device-id> shell am start -n dev.sctvdl.flutter.debug/dev.sctvdl.flutter.MainActivity` for that restore; Release/Profile uses `dev.sctvdl.flutter` as the package ID. Keep fixture files and outputs outside tracked source.

For resume-frame validation, use `integration_test/resume_frame_test.dart` with
the same define mechanism and a 30-second H264 fixture: solid red for the first
10 seconds, solid green thereafter. It resumes at 12 seconds, samples actual
Android texture pixels until the resumed frame renders, and checks
the retained green frame, session and bounds after cancelling a route gesture.
It also completes a return and checks the original artwork bounds. Route progress
is driven by the test; the system-input journey below validates OS gestures.

For the Android OOM regression, run the opt-in long-programme journey on a disposable runtime with a **192 MiB app heap limit**. It uses live metadata and streams a full episode; it does not create a download. It holds the initial paused player for 90 seconds, plays for 90 seconds, seeks, switches quality when the upstream episode has multiple sources, and opens two replacement sessions. The full application services remain alive throughout. Use `PLAYER_MEMORY_DATE=YYYY-MM-DD` to select a historical broadcast, or omit it for the latest date.

```sh
flutter test integration_test/playback_memory_test.dart -d <device-id> \
  --dart-define=LIVE_PLAYER_MEMORY=true
```

For a release-mode run, build an APK with `--target=integration_test/playback_memory_test.dart --dart-define=LIVE_PLAYER_MEMORY=true`, install it on that disposable device, and launch its main Activity. Capture `adb logcat` and sample `adb shell dumpsys meminfo --local dev.sctvdl.flutter` every two seconds. The `--local` option avoids calling into the app and forcing garbage collection; its PSS values are not allocated Java heap sizes. Confirm `dalvik.vm.heapgrowthlimit` and `dalvik.vm.heapsize` are both `192m`; changing only AVD RAM does not set the application heap limit. Require the `PLAYER_MEMORY_PASS` marker, advancing playback after seek/quality changes, and no OOM/crash. This is evidence for the tested stream/device, not a hard byte limit for every bitrate.

Repeat with a generated high-bitrate H264 MP4 to exercise memory pressure independently of the live programme's bitrate. Place a fixture longer than two minutes in the disposable app's `Documents/Downloads`, then pass `--dart-define=PLAYER_MEMORY_FILE=documents:Downloads/stress.mp4`. The journey keeps the same application services alive, resumes replacement sessions at 30-second intervals, and seeks to 90 seconds. Keep large fixtures and memory logs outside tracked source.

Add `--dart-define=PLAYER_MEMORY_STREAM=true` to serve that file over loopback HTTP with streaming backpressure. This exercises the official controller directly while keeping application services alive, without retaining the full fixture in Dart memory or relaxing the production CDN allowlist. The local-file and live-programme branches separately exercise the production playback adapter. Android Release builds reject cleartext HTTP by default; for this test only, add a temporary network-security configuration allowing `127.0.0.1`, build the test APK, then remove that configuration from source. Keep production HTTP policy unchanged. The same journey runs on disposable iOS simulators; sample the app process RSS and check native crash logs. It leaves ten seconds after player disposal for sampling. Simulator measurements do not establish physical iOS device jetsam limits.

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

This opt-in journey uses live metadata and paused native video, waits for initialization before checking the revealed surface, and verifies retained geometry and scroll state. Without `--pages`, the driver checks the original catalogue/exploration/archive cases.

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
