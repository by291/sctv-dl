# Android Client

**蜀台回看** is the native Kotlin and Jetpack Compose client for sctv-dl. It connects directly to the public programme service; no Web or Node deployment is required. The configured minimum is Android 10/API 29; release checks must cover the advertised OS/device matrix.

## Product

Browse and search programmes, save favourites, choose available broadcast dates, distinguish full episodes from clips, and play standard or smooth MP4 video. Native playback includes seeking, speed, fullscreen, and explicit picture-in-picture. Download one item or a selection to `Downloads/sctv-dl`, inspect actual progress, pause or resume new tasks, cancel, retry, manage selections, and play, open, share, or delete completed files. Search viewing history and resume unfinished programmes while paused; completed programmes restart from the beginning. Settings separately clears metadata/image caches and viewing history.

Product layouts, navigation and resource lifecycles are maintained in [Android Client Architecture](../docs/android.md).

## Setup and Build

Open this `android/` directory in an Android Studio release that supports Android Gradle Plugin 9.4.1. Install JDK 21, the stable Android 17 SDK platform (`android-37.0`), and Build Tools 37.0.0. Android Studio manages your untracked `local.properties`; command-line builds may instead use `ANDROID_HOME`. The checked-in Gradle 9.8.1 wrapper verifies its distribution checksum.

Run from the repository root on Windows:

```powershell
android/gradlew.bat -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
```

On macOS or Linux:

```sh
./android/gradlew -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
```

Outputs are `app/build/outputs/apk/debug/app-debug.apk` and `app/build/outputs/apk/release/app-release-unsigned.apk`. The debug APK is installable. The optimized release APK uses R8 and resource shrinking and requires your release signing identity before distribution. Signing keys and passwords must remain outside tracked files.

For separate release APKs per architecture, enable ABI splitting explicitly (use `gradlew.bat` on Windows):

```sh
./android/gradlew -p android :app:assembleRelease -PsplitPerAbi=true
```

This produces `app-armeabi-v7a-release-unsigned.apk`, `app-arm64-v8a-release-unsigned.apk`, and `app-x86_64-release-unsigned.apk` under `android/app/build/outputs/apk/release/`. CI uses this command for release artifacts. Each APK contains only its matching native libraries; shared Kotlin code and resources remain in every APK. Ordinary builds without the property keep a universal APK, including debug and instrumentation builds. All native APK variants retain the same Git-derived version code; these are standalone distribution artifacts, not legacy Google Play multi-APK uploads. Use an Android App Bundle for store-managed device delivery.

Build from a complete Git checkout with Git available on `PATH`. The displayed version is `0.1.1-<short-commit-id>`, and Android's installation `versionCode` is the number of commits reachable from `HEAD`. New descendant commits increase the code; rebuilding the same commit retains its version. A shallow checkout is rejected to prevent a smaller or repeated version code; run `git fetch --unshallow` first. Android CI fetches the complete history. The settings page reads the installed package version, including its commit suffix. Upstream compatibility headers keep their separate official APK version.

Debug and release use separate application IDs and launcher labels, so both can be installed on the same device. Each installation has its own app data, favourites, settings, and download history.

| Build type | Application ID         | Application name |
| ---------- | ---------------------- | ---------------- |
| Debug      | `dev.sctvdl.app.debug` | 蜀台回看 Debug   |
| Release    | `dev.sctvdl.app`       | 蜀台回看         |

Format Kotlin and Gradle scripts with `android/gradlew.bat -p android spotlessApply`. Compose functions follow the normal PascalCase convention; explicit imports, four spaces, 120-column source lines, and blank lines between declarations are enforced. Spotless reads the repository's `.editorconfig`. Follow [Android Instructions](AGENTS.md#readability) for logical grouping and contract comments that formatting cannot check. Dependency versions live in `gradle/libs.versions.toml`. AGP supplies built-in Kotlin for Android modules; do not apply the legacy `kotlin-android` plugin.

## Architecture

[Android Client Architecture](../docs/android.md) owns module boundaries, accepted programme state, playback, managed/legacy downloads, publication, history and backup. [Android Instructions](AGENTS.md) owns Kotlin/Compose conventions and native contribution rules; [Upstream API](../docs/upstream-api.md) owns shared response and transport contracts.

The application uses Hilt, typed Navigation 3 routes, feature modules and Kotlin-only domain contracts. `core:data` owns Room/DataStore and native transfers; `core:player` owns Media3; feature modules expose Route entry points. `checkModuleDependencies` verifies the configured project edges. Preserve database schemas, settings keys and serialized routes when reorganizing source.

## Tests

Unit tests live in `src/test`; device/UI tests live in `src/androidTest`. Use fakes, disposable databases and controlled upstream/download fixtures. Select regression coverage by the affected contract:

| Area            | Required evidence                                                                                                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Build and style | Gradle debug assembly, release assembly with R8, Android lint, Kotlin formatter/static analysis; existing Web checks for any shared tooling changes                              |
| Domain rules    | String/unsafe numeric IDs, invalid dates, last-record date deduplication, actual-quality fallback, duplicate URLs, explicit full-episode recognition, safe Unicode filenames     |
| Repositories    | Stub HTTP responses, malformed/business failures, empty-cache snapshots, cancellation and late replies, Room refresh transactions, DataStore defaults                            |
| Downloads       | Stub HEAD/Range, independent batch failures, duplicate taps, enqueue recovery, unknown length, system waiting/failure reasons, process recreation, removed files, local playback |
| Compose UI      | Catalogue to archive to playback/download; favourites; batch mode and back; quality-sheet dismissal; error retry; restored navigation                                            |
| Device UX       | Compact and expanded windows, light/dark/system appearance, 200% text, TalkBack, keyboard focus, rotation, predictive back, PiP, notification navigation                         |
| Media           | Live HEAD or small Range probe plus real device playback, seeking and quality switching; no full-video verification download                                                     |
| Performance     | Release startup and programme scrolling measurements; a baseline profile for the critical browse/play path                                                                       |

Run from the repository root, explicitly selecting the disposable device. Use `gradlew.bat` and set `ANDROID_SERIAL` in the shell on Windows.

```sh
./android/gradlew -p android :app:assembleDebugAndroidTest
ANDROID_SERIAL=<disposable-device-id> ./android/gradlew -p android connectedDebugAndroidTest --no-parallel
```

Use a disposable emulator or device; fixture downloads are removed after the test. On API 37, Espresso 3.7.0 currently calls the removed `InputManager.getInstance` method. Run Compose interaction tests on API 29 and use ADB/UI Automator or non-Espresso instrumentation for API 37 until the upstream test library supports it. This does not affect application playback or navigation at runtime.

Resource controls are local choices. For a constrained verification run, append `--no-daemon --no-parallel --max-workers=2 -Dorg.gradle.jvmargs="-Xmx1536m -Dfile.encoding=UTF-8" -Pkotlin.compiler.execution.strategy=in-process`. These flags are optional and do not describe a requirement for other developers' computers. Run emulator testing separately from builds when memory is limited.

If an emulator's `c2.goldfish.h264.decoder` fails to queue codec input, compare a disposable emulator launched with `-feature -HardwareDecoder` before changing application decoding policy. This diagnostic separates emulator codec configuration from application policy; physical-device decoders need their own coverage.

## Performance and CI

The Baseline Profile producer exercises startup, catalogue browsing, archive navigation, and paused player startup. It uses the production upstream service or existing metadata cache; the public service must be reachable when no cache exists. Automatic generation during normal builds is disabled, so assembling an APK never starts an emulator.

With one connected API 33+ device or emulator, generate and package a profile:

```powershell
android/gradlew.bat -p android :app:generateBaselineProfile
android/gradlew.bat -p android :app:assembleRelease
```

The plugin saves generated rules under `app/src/main/generated/baselineProfiles`. Review regenerated rules alongside changes to critical journeys. The optimized `benchmarkRelease` variant is locally debug-signed and profileable; production `release` remains unsigned. Compile the performance harnesses with `:baselineprofile:assemble :benchmark:assemble`.

Run `android/gradlew.bat -p android :benchmark:connectedBenchmarkReleaseAndroidTest` on a suitable physical device. The suite records cold startup and catalogue frame timing. Keep the device cool, idle, and on the same network/data conditions when comparing results. Emulator timing is not representative of user devices; profile generation on an emulator does not establish performance gains. See the official [Baseline Profile](https://developer.android.com/topic/performance/baselineprofiles/create-baselineprofile) and [Macrobenchmark](https://developer.android.com/topic/performance/benchmarking/macrobenchmark-overview) guides.

[Android CI](../.github/workflows/android.yml) explicitly configures Android command-line tools and installs the pinned SDK with `android-actions/setup-android`, uses JDK 21 and the verified wrapper, checks formatting/unit tests/lint, assembles app and performance APKs, and preserves reports. It does not rely on the runner image providing `sdkmanager` on `PATH`. Connected device tests and physical performance measurements run separately.

A separate CI job resolves and submits the Gradle dependency graph on pushes to `main` and manual runs on `main`, so Dependabot can report vulnerable dependencies. The [Dependabot configuration](../.github/dependabot.yml) checks the Android version catalogue, modules, included build logic, and Gradle Wrapper every week. See [Repository Maintenance](../docs/maintenance.md#ci-and-dependency-updates) for update grouping and security settings.

### Dependency Security

The submitted graph retains all resolved dependencies and uses the plugin's [scope configuration](https://github.com/gradle/github-dependency-graph-gradle-plugin#controlling-the-scope-of-dependencies-in-the-dependency-graph):

| Scope         | Resolved dependencies                                                                                                |
| ------------- | -------------------------------------------------------------------------------------------------------------------- |
| `runtime`     | `:app`'s `releaseRuntimeClasspath`, including transitive dependencies from its core and feature modules.             |
| `development` | All other resolutions: build plugins, processors, debug tools, tests, benchmarks, and the Baseline Profile producer. |

When the same package version appears in both scopes, it is reported as `runtime`. These labels describe dependency resolution before release shrinking; they do not prove that vulnerable code is reachable. Development dependencies can still affect build and CI security, and their alerts remain enabled.

GitHub [cannot automatically update undeclared Gradle transitive dependencies](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#gradle). An updater failure such as `security_update_dependency_not_found` therefore needs assessment of the advisory and the owning dependency, rather than a scope change or blanket dismissal.

Check the alert's scope and affected behaviour, then trace the dependency in the relevant module and configuration. For example, check whether Netty is on the release app's dependency path:

```powershell
android/gradlew.bat -p android :app:dependencyInsight --configuration releaseRuntimeClasspath --dependency io.netty:netty-codec-http
```

For build plugin dependencies, inspect the owning project's `buildEnvironment` report. Upgrade the declared parent library or plugin in the version catalogue or build logic, run the Android checks above, and confirm that the next submitted graph removes the vulnerable version. Avoid adding an unused direct dependency or forcing a version solely to make the updater succeed. If no compatible fix is available, record the dependency path, exposure assessment, and upstream fix to track before dismissing an alert.

## Release acceptance

Keep these device and distribution checks separate from JVM tests and APK assembly:

- The API 29 decoded-frame pixel and fullscreen status-bar assertions need resolution before claiming a fully green minimum-OS device suite. API 37 has separate Espresso `InputManager.getInstance` compatibility and emulator navigation-inset constraints; complementary runs do not establish full coverage on either OS.
- Exercise TalkBack, system reduced motion, 200% text, keyboard input, compact/expanded windows, real predictive-back gestures, PiP and physical decoder/audio behaviour.
- Verify real VPN/cellular transitions, manufacturer background policies and prolonged execution quotas. Controlled lease/network fixtures do not establish these OS behaviours.
- Test OS backup/device transfer, upgrade with a real legacy DownloadManager task, file-deletion consent for externally owned media and cleanup during a delayed image request. A database migration or copied user-database fixture is narrower evidence.
- Measure performance on physical devices and complete installed release-mode journeys. Production signing, store publication and actual hosted CI results remain separate from local build success.
