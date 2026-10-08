# Android Client

**蜀台回看** is the native Kotlin and Jetpack Compose client for sctv-dl. It connects directly to the public programme service; no Web or Node deployment is required. Android 10 and newer are supported.

## Product

Browse and search programmes, save favourites, choose available broadcast dates, distinguish full episodes from clips, and play standard or smooth MP4 video. Native playback includes seeking, speed, fullscreen, and explicit picture-in-picture. Download one item or a selection to `Downloads/sctv-dl`, inspect actual system progress, cancel, retry, play local files, and open or share a completed file.

The Material 3 theme pairs a restrained vermilion accent with neutral surfaces and supports light, dark, system mode, and optional system wallpaper colours on Android 12+. The primary destinations are programme library, downloads, and settings. A compact television brand identifies the library. All programmes and favourites are tabs inside it with independent filters and scroll positions. The unfiltered all-programmes view includes a native exploration card using real artwork; users can open the featured programme or choose another, without an automatic carousel. Compact windows show bottom navigation on primary pages, while programme details and playback are separate pages. Wider windows use a rail and a catalogue/detail layout. Archive pages expose direct recent-date shortcuts and a full date sheet; batch actions appear only in selection mode. Text scaling changes card layout without hiding actions.

## Setup and Build

Open this `android/` directory in an Android Studio release that supports Android Gradle Plugin 9.3.3. Install JDK 21, the stable Android 17 SDK platform (`android-37.0`), and Build Tools 37.0.0. Android Studio manages your untracked `local.properties`; command-line builds may instead use `ANDROID_HOME`. The checked-in Gradle 9.5.0 wrapper verifies its distribution checksum.

Run from the repository root on Windows:

```powershell
android/gradlew.bat -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
```

On macOS or Linux:

```sh
chmod +x android/gradlew
./android/gradlew -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
```

Outputs are `app/build/outputs/apk/debug/app-debug.apk` and `app/build/outputs/apk/release/app-release-unsigned.apk`. The debug APK is installable. The optimized release APK uses R8 and resource shrinking and requires your release signing identity before distribution. Signing keys and passwords must remain outside tracked files.

Format Kotlin and Gradle scripts with `android/gradlew.bat -p android spotlessApply`. Compose functions follow the normal PascalCase convention; explicit imports, four spaces, and 120-column source lines are enforced. Dependency versions live in `gradle/libs.versions.toml`. AGP supplies built-in Kotlin for Android modules; do not apply the legacy `kotlin-android` plugin.

## Architecture

| Module            | Responsibility                                                                               |
| ----------------- | -------------------------------------------------------------------------------------------- |
| `app`             | Single activity, Navigation 3 routes, feature ViewModels, Compose screens                    |
| `core:domain`     | Android-free contracts, IDs, quality/full-episode/filename/sorting policies                  |
| `core:data`       | Retrofit/OkHttp, validation, Room snapshots/favourites/downloads, DataStore, DownloadManager |
| `core:design`     | Material 3 colour/shape tokens and reusable stateless components                             |
| `core:player`     | Media3 ExoPlayer/MediaSession, controller, surface and controls                              |
| `baselineprofile` | Startup, catalogue/archive/player profile generation                                         |
| `benchmark`       | Release startup and catalogue scroll Macrobenchmarks                                         |

Hilt provides repository implementations. ViewModels expose immutable screen state and actions; UI collects it with lifecycle awareness. Catalogue and favourites share repository data and preserve independent search/sort state. Room snapshots are keyed by catalogue, programme, and programme/date. Successful empty responses are cached atomically; failures preserve older content with visible error feedback. Request cancellation and generation checks reject stale results. Metadata responses are read with a 2 MiB limit before full-body buffering. DataStore stores theme, dynamic colours, initial quality, and the default network policy for new downloads.

The public upstream endpoint schemas and security constraints are documented in [Upstream API](../docs/upstream-api.md). Native transport validates the same IDs and URL families, preserves the `video`/`videoStandard` mapping, and uses `https://scgc.video.play/` as the media Referer. Application-controlled metadata, cover, and player clients do not follow redirects. Android's system transfer service owns its own redirect handling.

## Downloads and Playback

Download records persist before transfer submission. A transaction prevents duplicate active jobs for the same content and actual quality. Each attempt has a safe unique filename capped at 255 UTF-8 bytes without splitting code points, preserving the quality and unique suffix. Unavailable requested quality falls back to an actual available variant and is reported to the user. One failed batch member does not discard successfully queued members.

When the application returns, reconciliation queries owned system jobs and checks completed content URIs. Querying and applying status shares the submission transition lock, preventing an old system snapshot from invalidating a new task. A submission interrupted between system enqueue and database update can attach only to a unique URL/destination match. The system description records the planned filename at enqueue, making pending jobs recoverable before a local URI exists. Multiple matches remain unresolved until the old system jobs are handled. Waiting reasons, actual bytes, failed transfers, and externally removed files are shown truthfully. Failed/interrupted tasks remain in the first section with a retry action. Files with unknown total size show bytes and indeterminate progress.

The system continues transfers after the application leaves the foreground. Network policy is fixed per task; changing the default affects future tasks. Pause/resume is not offered. Cancelling a task removes its system job and partial file. Removing a terminal history entry leaves the file in public Downloads. Sharing and external opening use content URIs with temporary read grants; no broad storage permission is requested.

Playback starts paused. A quality change keeps the same ExoPlayer, position, and intent to play. Short landscape windows constrain video height and allow scrolling to controls; fullscreen and PiP retain their bounded video layout. Ordinary backgrounding pauses. Picture-in-picture is entered explicitly and can continue playback when the device supports it. Navigation disposal releases the player and media session after the leave animation. Theme/settings can be backed up; cached content and runtime transfer IDs are excluded.

Android 10 embeds Media3's native TextureView through Compose `AndroidView` to avoid black backgrounds and stale layers during rotation in Compose external surfaces. The controls remain Compose. Newer runtimes use Media3's Compose ContentFrame and SurfaceView. This fallback covers the public non-DRM MP4 sources; see the related [upstream issue](https://github.com/androidx/media/issues/3285). A device test decodes a generated MP4 and checks the actual window background outside the video.

## Tests

Unit tests cover upstream validation, caching/cancellation, preferences, feature state, player lifecycle policy, preflight, submission, retries, cancellation, and restart reconciliation. Device tests use disposable databases and controlled download fixtures.

```powershell
android/gradlew.bat -p android :core:domain:test :core:data:testDebugUnitTest :core:player:testDebugUnitTest :app:testDebugUnitTest
android/gradlew.bat -p android :app:connectedDebugAndroidTest :core:data:connectedDebugAndroidTest :core:player:connectedDebugAndroidTest
```

Use a disposable emulator or device; fixture downloads are removed after the test. On API 37, Espresso 3.7.0 currently calls the removed `InputManager.getInstance` method. Run Compose interaction tests on API 29 and use ADB/UI Automator or non-Espresso instrumentation for API 37 until the upstream test library supports it. This does not affect application playback or navigation at runtime.

Resource controls are local choices. For a constrained verification run, append `--no-daemon --no-parallel --max-workers=2 -Dorg.gradle.jvmargs="-Xmx1536m -Dfile.encoding=UTF-8" -Pkotlin.compiler.execution.strategy=in-process`. These flags are optional and do not describe a requirement for other developers' computers. Run emulator testing separately from builds when memory is limited.

If an emulator's `c2.goldfish.h264.decoder` fails to queue codec input, compare a disposable emulator launched with `-feature -HardwareDecoder` before changing application decoding policy. API 37 media verification on this workstation used that software-decoder path. Physical-device decoders need their own coverage.

### Initial Verification

Verified on 2026-10-07: formatting, Android lint, 50 unit tests, debug and R8 release assemblies, and both performance harness assemblies. Twelve Compose interaction tests and three UI Automator window/restoration tests passed on API 29. The same three UI Automator tests, four storage/system-download tests, and two native-player tests passed on API 37; storage and native-player tests also passed on API 29. Recovery includes a real Wi-Fi-only pending job with no local file URI. The baseline profile producer completed both real journeys, and its compiled profile is packaged in the optimized APK. A locally signed `benchmarkRelease` APK was installed and exercised against live catalogue, archive, and playback data after shrinking on both API 29 and API 37.

Runtime inspection covered real covers, online playback, seeking, quality switching, rotation, explicit PiP, a cancelled back gesture, dark appearance, 200% text, keyboard search, and expanded catalogue/archive panes. System download fixtures verified actual status, bytes, Referer, persistence, and removed-file detection. Existing Web checks and the production build also passed.

The final API 29 cold boot initially gave all Android processes a stale 16 MiB VM heap limit despite a later 512 MiB system property. Restarting Android services in that disposable emulator restored normal allocation; the unchanged optimized APK then played live video with an empty crash buffer. No application heap override was added.

Physical-device performance measurements, a TalkBack walkthrough, store signing, and a remote CI run remain separate verification steps. API 37 Compose interaction coverage is limited by the Espresso issue described above. Emulator results establish behaviour on those tested runtimes, not identical performance or decoder behaviour on every device.

See [Client Design](../docs/android-client-design.md) for acceptance criteria and [Agent Instructions](AGENTS.md) for native contribution constraints.

### Native Layout Revision Verification

Verified on 2026-10-08: formatting, Android lint, 54 unit tests, debug and R8 release assemblies, 11 UI Automator navigation/archive/exploration/window tests, and four storage/system-download device tests on API 37. Manual checks covered live catalogue and archive data, light/dark appearance, a 320 dp window at 200% text, keyboard search, empty favourites/results, offline retry recovery, and expanded catalogue/archive panes. Eleven Compose interaction tests were blocked by the API 37 Espresso incompatibility above; this revision was not rerun on API 29 or physical devices.

## Performance and CI

The Baseline Profile producer exercises startup, catalogue browsing, archive navigation, and paused player startup. It uses the production upstream service or existing metadata cache; the public service must be reachable when no cache exists. Automatic generation during normal builds is disabled, so assembling an APK never starts an emulator.

With one connected API 33+ device or emulator, generate and package a profile:

```powershell
android/gradlew.bat -p android :app:generateBaselineProfile
android/gradlew.bat -p android :app:assembleRelease
```

The plugin saves generated rules under `app/src/main/generated/baselineProfiles`. Review regenerated rules alongside changes to critical journeys. The optimized `benchmarkRelease` variant is locally debug-signed and profileable; production `release` remains unsigned. Compile the performance harnesses with `:baselineprofile:assemble :benchmark:assemble`.

Run `android/gradlew.bat -p android :benchmark:connectedBenchmarkReleaseAndroidTest` on a suitable physical device. The suite records cold startup and catalogue frame timing. Keep the device cool, idle, and on the same network/data conditions when comparing results. Emulator timing is not representative of user devices; profile generation on an emulator does not establish performance gains. See the official [Baseline Profile](https://developer.android.com/topic/performance/baselineprofiles/create-baselineprofile) and [Macrobenchmark](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-overview) guides.

[Android CI](../.github/workflows/android.yml) installs the pinned SDK, uses JDK 21 and the verified wrapper, checks formatting/unit tests/lint, assembles app and performance APKs, and preserves reports. Connected device tests and physical performance measurements run separately.
