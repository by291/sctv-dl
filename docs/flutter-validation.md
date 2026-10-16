# Flutter Validation

This record separates implementation, automated checks, native runtime evidence and release distribution. Results below were obtained on 2026-10-16–17 in Asia/Shanghai from the Flutter implementation following plan commit `7bff698`. Grouped local implementation commits were authorized on 2026-10-17. The [Flutter README](../flutter/README.md) owns setup, commands and architecture; the [design](superpowers/specs/2026-10-16-flutter-mobile-design.md) owns the product contract.

## Environment and Runtime Coverage

- Flutter 3.47.6 stable / Dart 3.13.5; `flutter doctor -v` passed.
- Xcode 27.0 (`27A266a`) and CocoaPods 1.17.0.
- Android SDK 37 and NDK `28.2.13676358`; portable Java/Kotlin bytecode target 17. Native JVM HTTP tests also passed with Java 17 and the host's Java 25.
- Disposable Android 17/API 37 emulator, arm64, `emulator-5560`.
- Disposable iOS 27 iPhone 18 Pro simulator, `32DA051E-59BF-4634-B8BC-3C773ACDA05F`.

Only these disposable devices were used; the user's existing emulators were left alone. Device identifiers are evidence for this run, not portable configuration.

## Automated and Runtime Evidence

| Check                                     | Observed result and boundary                                                                                                                                                                                                                                                                                                                              |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flutter application checks                | `flutter analyze --fatal-infos` passed with no issues; all 119 Dart tests passed. Formatting covered 74 application/test/driver files without changes. Drift generation reproduced the existing generated source.                                                                                                                                         |
| Release compilation                       | Final APK (73.6 MB), App Bundle (70.6 MB) and unsigned iOS app (25.5 MB) compiled successfully. Native JVM HTTP tests and instrumentation compilation passed through the portable wrapper used by CI.                                                                                                                                                     |
| Root Web checks                           | `pnpm check` passed: 54 test files, 429 tests, type checking, ESLint and Prettier. `pnpm build` passed.                                                                                                                                                                                                                                                   |
| Android playback allocation               | An actual Media3 allocator regression failed before the repair and now stops loading at a 24 MiB sample target, starts at that limit and resumes after consumption. Prefetch horizon is 30 seconds, with no heap-size or HTTP protocol workaround.                                                                                                        |
| Controlled playback                       | Android and iOS decoded a generated three-second H264 MP4, verified required headers, paused initialization, seek/speed and local playback, and rejected HTTP redirects without requesting the destination. Android additionally exercises MediaStore `content://` playback.                                                                              |
| Controlled transfers                      | Two native fixture tests passed on each OS. They cover holding-queue maximum two, actual bytes, unknown totals, required headers, publication/file inspection/deletion and ignored-Range resume behavior. Resume byte-integrity assertions run when native resume is available; unavailable resume is covered by repository tests.                        |
| Android publication and notification host | Four instrumentation cases passed: partial and full-length pending MediaStore rows are replaced by visible verified publications while retaining the private source; notification acknowledgment matches the native task and preserves unrelated extras.                                                                                                  |
| Full application                          | Both OS families passed the opt-in live application journey: production bootstrap/SQLite/plugins, catalogue of 40 programmes, keyboard search, broadcast archive, live media initialized paused, return navigation, Downloads, dark theme and resource cleanup. This journey creates no live download.                                                    |
| Sampled live media                        | One allowlisted live MP4 returned HEAD 200, `video/mp4`, length 561408225 and `Accept-Ranges: bytes`. No response body was downloaded.                                                                                                                                                                                                                    |
| Restore and lifecycle regressions         | Widget/controller tests cover route cancellation, stale cache/network/history replies, durable local routes without online fallback, shared resume/completion, query/date/batch restoration, current quality, paused native-error retry, failed switch rollback, source-switch/background races, cancelled Cupertino back, short landscape and 200% text. |
| Native backup configuration               | Production iOS bootstrap creates and excludes runtime DB, downloader task/resume/paused/metadata folders, native Preferences and downloaded media before transfers initialize. The native channel reads back the exclusion attribute. Android allowlists only the user database and journals. An actual backup/restore has not been performed.            |

The first installed Android release exposed a large-media OOM that short decode fixtures did not reveal. The inherited 109-minute prefetch horizon and automatic video/audio allocator target of about 137.5 MiB left insufficient headroom in the tested 192 MiB Java heap. A real native allocator regression drove the byte-threshold repair. The repaired release survived a 90-second observation against the same 561 MB programme with a stable process and sampled Java-heap allocation around 62–63 MiB after initial buffering. Playback advanced, pause worked, and seeking to 07:18 remained paused without native exceptions. The subsequent control-text contrast repair passed its rendered-text regression and inspection of the final installed APK, which restored 07:13 paused. This is a targeted release regression, not a general load benchmark or long background-transfer result.

The player is the licensed, locally patched [better_player_plus 2.0.0](../flutter/packages/better_player_plus/LOCAL_PATCHES.md). Native fixtures exposed duplicate User-Agent headers, extensionless MediaStore IDs, and pending-row lookup behavior; those were repaired at their owning boundaries. The complete download repository also tests durable publication commit before private cleanup and recovery from transient bootstrap failures.

## Reproduce Device Checks

Run from `flutter/`, with a disposable device selected explicitly:

```sh
flutter test integration_test/downloads_test.dart -d <device-id>
flutter test integration_test/playback_test.dart -d <device-id> \
  --dart-define=PLAYBACK_FIXTURE_BASE64=<base64-of-a-small-H264-mp4>
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/application_test.dart -d <device-id> \
  --dart-define=LIVE_APPLICATION_SMOKE=true
ANDROID_SERIAL=<disposable-android-id> ./android/gradlew -p android \
  :app:connectedDebugAndroidTest --no-daemon
```

The live journey is opt-in and requires current upstream availability. Its screenshot driver writes to ignored `build/qa/`; device integration runs use native plugins rather than substituting fake backends. Dart unit/controller/widget tests separately use controlled HTTP services, disposable SQLite and fake platform boundaries. Do not treat those tests as device evidence.

## Remaining Acceptance and Distribution

- Android 10/API 29 and iOS 15 are configured support floors, but minimum-version and physical-device journeys remain unverified.
- The iOS simulator reports PiP unavailable; its explicit native PiP case is skipped, never counted as passed. Physical PiP, audio focus/interruption, headphone/Bluetooth route loss and system fullscreen behavior still need device acceptance.
- Sustained background transfers, suspension/relaunch, OS process reclamation, user force-quit, Wi-Fi/network loss and long Android execution windows remain unverified. A short foreground transfer proves none of these. Native jobs remain system-owned and the app reconciles them on launch/resume.
- Interactive share/export sheets, export cancellation, URI grants, uninstall retention and actual backup/restore remain manual acceptance work. Publication recovery, missing files and deletion have the narrower automated evidence above.
- TalkBack, VoiceOver, physical phone/tablet layouts, reduced-motion system settings and complete installed release-mode download/local-playback journeys remain pending. Existing widget coverage and screenshots establish narrower layout/interaction behavior.
- Android release artifacts use debug signing for local validation. iOS release compilation is unsigned. Production keys, Apple team/provisioning, store submissions, deployment and hosted CI execution have not been performed.

Review findings about initialization retry, notification consumption, media errors, backup ownership, safe areas and publication recovery were addressed before final acceptance checks. This document does not promote any pending device or distribution item to passed based on a build or a fake-backed test.
