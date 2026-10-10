# Android Client

**蜀台回看** is the native Kotlin and Jetpack Compose client for sctv-dl. It connects directly to the public programme service; no Web or Node deployment is required. Android 10 and newer are supported.

## Product

Browse and search programmes, save favourites, choose available broadcast dates, distinguish full episodes from clips, and play standard or smooth MP4 video. Native playback includes seeking, speed, fullscreen, and explicit picture-in-picture. Download one item or a selection to `Downloads/sctv-dl`, inspect actual system progress, cancel, retry, play local files, and open or share a completed file.

The Material 3 theme pairs a restrained vermilion accent with neutral surfaces and supports light, dark, system mode, and optional system wallpaper colours on Android 12+. The primary destinations are programme library, downloads, and settings. A compact television brand identifies the library, with search expanding inside its toolbar. All programmes and favourites are tabs inside it with independent filters and scroll positions. The unfiltered all-programmes view includes a native exploration card with larger real artwork in a lightly tilted themed frame; users can open the featured programme or choose another, without an automatic carousel. Library and archive pages check for updates automatically on entry, without pull-to-refresh gestures. Cached pages stay usable without loading indicators; changed results show a toolbar update icon with a theme-coloured dot and the accessible label `有新内容，点击更新`, and remain pending until accepted. The action does not shift the visible content. Programme cards keep a compact title panel without a reserved empty line or repeated caption. Returning to a retained page or resuming the app does not accept pending results. Compact windows show bottom navigation on primary pages, while programme details and playback are separate pages. Wider windows use a rail and a catalogue/detail layout. Archive pages expose direct recent-date shortcuts and a full date sheet; batch actions appear only in selection mode. Text scaling changes card layout without hiding actions.

The initial catalogue load uses noninteractive skeletons for the exploration, summary, and card grid, with [Compose Shimmer](https://valentinilk.github.io/compose-shimmer/) and a static fallback when system animations are disabled. Exploration remains visible as the first catalogue load completes. Uncached archives also preserve their header, date shortcuts, and content-card structure with noninteractive skeletons. A changed broadcast with no cache uses the same content skeletons. Archive headings show the selected broadcast date and separate full-episode/clip counts; tapping an item opens playback. The playback page places a labelled download button below the complete title and broadcast context. Batch mode uses compact cards with a leading checkbox and whole-card selection. Batch selection keeps its presented rows stable and hides the update action until selection ends. Refresh failures use one page-level retry action. Playback carries the accepted item and broadcast context from the archive, so pending metadata cannot change the source or download request.

## Setup and Build

Open this `android/` directory in an Android Studio release that supports Android Gradle Plugin 9.3.3. Install JDK 21, the stable Android 17 SDK platform (`android-37.0`), and Build Tools 37.0.0. Android Studio manages your untracked `local.properties`; command-line builds may instead use `ANDROID_HOME`. The checked-in Gradle 9.5.0 wrapper verifies its distribution checksum.

Run from the repository root on Windows:

```powershell
android/gradlew.bat -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
```

On macOS or Linux:

```sh
./android/gradlew -p android spotlessCheck check :app:assembleDebug :app:assembleRelease
```

Outputs are `app/build/outputs/apk/debug/app-debug.apk` and `app/build/outputs/apk/release/app-release-unsigned.apk`. The debug APK is installable. The optimized release APK uses R8 and resource shrinking and requires your release signing identity before distribution. Signing keys and passwords must remain outside tracked files.

Format Kotlin and Gradle scripts with `android/gradlew.bat -p android spotlessApply`. Compose functions follow the normal PascalCase convention; explicit imports, four spaces, and 120-column source lines are enforced. Dependency versions live in `gradle/libs.versions.toml`. AGP supplies built-in Kotlin for Android modules; do not apply the legacy `kotlin-android` plugin.

## Architecture

| Module               | Responsibility                                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `app`                | Application/Activity, typed navigation, global settings/download feedback, foreground reconciliation, playback host |
| `feature:programmes` | Catalogue, favourites, archive, accepted updates, programme/episode components                                      |
| `feature:downloads`  | Task lists/actions and native file launchers                                                                        |
| `feature:settings`   | Preference screen and mutations                                                                                     |
| `feature:player`     | Online/local routes, playback state, destination session lifetime, host contract                                    |
| `core:domain`        | Android-free models, repository contracts, quality/full-episode/filename/sorting policies                           |
| `core:data`          | Validated HTTP, Room snapshots/favourites/tasks, DataStore, DownloadManager and recovery                            |
| `core:design`        | Generic Material 3 theme/tokens, brand, state feedback and loading primitives                                       |
| `core:ui`            | Application covers/transitions, quality sheet, outcome/error text and settings theme adapter                        |
| `core:player`        | Media3 session, playback models/controller, surface and controls                                                    |
| `baselineprofile`    | Startup and catalogue/archive/player profile generation                                                             |
| `benchmark`          | Release startup and catalogue scroll Macrobenchmarks                                                                |

Feature modules expose Route composables and small immutable contracts; screens, ViewModels, and helpers are internal. Features depend on shared core contracts and presentation, never siblings, `app`, or data implementations. Core modules never import features. `checkModuleDependencies`, included in `check`, validates actual configured Gradle project dependencies. Android/Compose/Hilt library defaults are shared through `build-logic`, with versions in the existing catalogue.

Within modules, packages follow subjects: domain `common/programme/media/download/settings/repository`; data `programmes/favourites/downloads/settings/database/network/di`; design `theme/components`; player infrastructure `model/controller/media3/ui`. Data stores, remote parsers and platform gateways stay under the subject they implement. Related small declarations stay together. `CachedProgrammeRepository`, `ProgrammeResponseParser`, `DownloadManagerRepository`, `DownloadManagerGateway`, `EpisodeCard`, and `DownloadQualitySheet` name their exact responsibilities.

`AppViewModel` provides lifecycle-collected global settings and durable download feedback. Each feedback has an identity so dismissing an older snackbar cannot acknowledge a newer result. Catalogue observation remains rooted in the app to retain accepted state across destinations; features own its state processing. The programme library retains separate catalogue/favourite positions for its expanded pane across archive replacement and resizing. Each visible pane owns its own grid controller, including overlapping navigation entries. App navigation carries the accepted archive selection into the player without sibling imports. `PlaybackHost` separates Activity window/PiP operations from destination session ownership. Persisted schema, settings keys/enums, application ID, and serialized route names remain compatible.

Hilt provides repository implementations. ViewModels expose immutable screen state and actions; UI collects it with lifecycle awareness. Catalogue and favourites share repository data and preserve independent search/sort state. Room snapshots are keyed by catalogue, programme, and programme/date. Successful empty responses are cached atomically; failures preserve older content with visible error feedback. Request cancellation and generation checks reject stale results. Metadata responses are read with a 2 MiB limit before full-body buffering. DataStore stores theme, dynamic colours, initial quality, and the default network policy for new downloads.

The public upstream endpoint schemas and security constraints are documented in [Upstream API](../docs/upstream-api.md). Native transport validates the same IDs and URL families, preserves the `video`/`videoStandard` mapping, and uses `https://scgc.video.play/` as the media Referer. Application-controlled metadata, cover, and player clients do not follow redirects. Android's system transfer service owns its own redirect handling.

## Downloads and Playback

Download records persist before transfer submission. A transaction prevents duplicate active jobs for the same content and actual quality. Each attempt has a safe unique filename capped at 255 UTF-8 bytes without splitting code points, preserving the quality and unique suffix. Unavailable requested quality falls back to an actual available variant and is reported to the user. One failed batch member does not discard successfully queued members.

When the application returns, reconciliation queries owned system jobs and checks completed content URIs. Querying and applying status shares the submission transition lock, preventing an old system snapshot from invalidating a new task. A submission interrupted between system enqueue and database update can attach only to a unique URL/destination match. The system description records the planned filename at enqueue, making pending jobs recoverable before a local URI exists. Multiple matches remain unresolved until the old system jobs are handled. Waiting reasons, actual bytes, failed transfers, and externally removed files are shown truthfully. Failed/interrupted tasks remain in the first section with a retry action. Files with unknown total size show bytes and indeterminate progress.

The system continues transfers after the application leaves the foreground. Network policy is fixed per task; changing the default affects future tasks. Pause/resume is not offered. Cancelling a task removes its system job and partial file. Removing a terminal history entry leaves the file in public Downloads. Sharing and external opening use content URIs with temporary read grants; no broad storage permission is requested.

Playback starts paused. Media3 Compose progress state drives a Material3 slider with a contiguous track and vertical seek thumb; Media3 time and play/pause controls overlay the video. Speed, quality, and fullscreen share the lower row; PiP sits at the upper right. Speed and quality choices open upward in translucent video menus, highlight the current option with theme accent text, and scroll within the video height. Controls stay visible while paused or interacting and hide after 3.5 seconds of uninterrupted playback, respecting accessibility timeouts. A quality change keeps the same ExoPlayer, position, and intent to play. Short landscape windows reserve enough video height for controls and allow scrolling to programme context and downloads; fullscreen and PiP retain their bounded video layout. Ordinary backgrounding pauses. Picture-in-picture is entered explicitly and can continue playback when the device supports it. Navigation disposal releases the player and media session after the leave animation. Theme/settings can be backed up; cached content and runtime transfer IDs are excluded.

Android 10 embeds Media3's native TextureView through Compose `AndroidView` to avoid black backgrounds and stale layers during rotation in Compose external surfaces. The controls remain Compose. Newer runtimes use Media3's Compose ContentFrame with TextureView so decoded video follows page opacity and predictive-back transforms without lingering until disposal. This fallback covers the public non-DRM MP4 sources; see the related [upstream issue](https://github.com/androidx/media/issues/3285). A device test decodes a generated MP4 and checks the actual window background outside the video.

## Tests

Unit tests cover upstream validation, caching/cancellation, preferences, feature state, player lifecycle policy, preflight, submission, retries, cancellation, and restart reconciliation. Device tests use disposable databases and controlled download fixtures.

```powershell
android/gradlew.bat -p android check
android/gradlew.bat -p android connectedDebugAndroidTest
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

The subsequent toolbar-search and pull-refresh revision passed the same build/unit checks, 14 UI Automator cases, and four data-device tests. Manual checks covered native keyboard input, empty results, narrow dark appearance at 200% text, expanded toolbar search, initial loading/error states, and live catalogue/archive pull refresh after restarting the disposable emulator. API 37 Compose tests were not rerun for this follow-up; their existing Espresso limitation still applies.

Verified on 2026-10-09 for the exploration/archive refinement: formatting, lint, 54 unit tests, debug and R8 release assemblies, and 19 UI Automator cases passed. Device regressions cover exploration after asynchronous first loading, a single initial-content spinner, one retry for simultaneous date/content failures, whole-card selection, and disabled selection without media. Manual checks covered live first entry, date/count headings, long and short clip titles, quality-sheet dismissal, selected cards, a dark 320 dp window at 200% text, and expanded panes. The four data-device cases passed after rechecking `aQueuedJobRetainsItsPlannedIdentityBeforeAnyFileExists`, which initially raced the emulator's Wi-Fi transition. Initial UI runs stalled in emulator graphics teardown; the final group passed with guest Vulkan disabled and the refresh fixture completed before activity teardown. The existing API 37 Compose/Espresso limitation remains; this refinement was not rerun on API 29 or physical devices.

The subsequent skeleton and playback-entry revision passed formatting, lint, 54 unit tests, debug and R8 release builds, both performance harness assemblies, and 24 UI Automator cases on API 37. New device coverage verifies skeleton transitions to errors/empty results, retained cards during cached refresh, whole-card playback, unavailable media, and player download context with no task before quality selection. Manual checks covered real cold-start skeletons, themed pull indicators, long/short clip cards, paused player entry, quality-sheet dismissal, dark 320 dp windows at 200% text, wide archive/player layouts, and fullscreen restoration. The live MP4 HEAD returned 200 with the required Referer; no real download task was created. The updated Compose archive/batch journey compiled but was not run because of the existing API 37 Espresso limitation; API 29 and physical devices were not available for this revision. Performance harness compilation does not claim regenerated profiles or new performance measurements.

The automatic-entry refresh revision passed formatting, lint, 66 unit tests, debug and R8 release builds, and 28 UI Automator cases. After the final full-episode skeleton sizing correction, 12 affected device cases passed again. Coverage includes retained cached rows without spinners or pull actions, explicit acceptance of changed or empty results, duplicate-request guards, stable batch selection, and accepted playback/download context. Manual checks confirmed a 39-row fixture staying visible until acceptance of the live 40-row catalogue, refreshed archive timestamps after app resume, cold archive skeletons, dark 320 dp windows at 200% text with animations disabled, and expanded panes. No real download task was created. The existing API 37 Compose/Espresso limitation still applies; API 29, physical devices, and data-device tests were not rerun for this revision.

The compact-card and toolbar-update refinement was verified on 2026-10-10: formatting, lint, 66 unit tests, debug and R8 release assemblies, and 28 UI Automator cases passed. The device invocation initially included a misspelled navigation test class; the 24 actual cases passed and the four correctly named navigation cases then passed separately. Pending updates do not move the library or archive content, remain explicitly accepted, and stay hidden during batch selection. Manual checks covered real cached catalogue and archive updates, compact one-line title panels, light/dark appearance, 320 dp windows at 200% text, keyboard search, retained cached content after upstream connection failures, and wide layouts. Ordinary one-line programme cards were about 25% shorter on the same device. The existing API 37 Compose/Espresso limitation remains; API 29, physical devices, and data-device cases were not rerun for this layout-only refinement.

The subsequent archive-header and exploration-artwork refinement passed formatting, lint, 66 unit tests, debug and R8 release builds, and 16 affected UI Automator cases on API 37. Manual checks used real cached metadata and covered enlarged tilted artwork, favourite interaction, light/dark appearance, 320 dp windows with normal and 200% text, keyboard search with empty results, and expanded catalogue/archive panes. Loading/error/empty transitions and explicit update acceptance remained covered by the device regressions. The final horizontal layout also passed a fresh build/unit recheck and five archive/update device cases. The existing Compose/Espresso limitation remains; API 29, physical devices, and data-device tests were not rerun for this presentation-only change.

### Feature Module Migration Verification

Verified on 2026-10-11: formatting, Android lint, the configured module-dependency check, 72 unit tests, debug and R8 release builds, both performance harness assemblies, and all relocated test APK assemblies passed. An injected sibling-feature dependency was rejected as expected. The Unix wrapper has executable mode `100755`, and CI invokes it directly.

Forty-eight distinct UI Automator/storage/media device cases passed across focused API 37 invocations. Coverage includes accepted archive/playback context, matching host disposal, a live session retained during navigation exit, fullscreen orientation/status-bar restoration, and independent catalogue/favourite pane positions across archive replacement and compact/expanded resizing. The Room v1 schema remains byte-identical. The system-download fixture now waits for actual Wi-Fi teardown before asserting a pending job; the navigation fixture uses the same saveable-entry decorator as the app.

Both baseline profile journeys passed, regenerated rules use the moved packages, and compiled profiles are packaged in the optimized release APK. A locally debug-signed, optimized `benchmarkRelease` APK passed live catalogue/archive/paused-player navigation, explicit PiP entry and return, light/dark inspection, native keyboard search, and empty results. Live expanded-pane checks retained the same row IDs and pixel offsets after both archive replacement and window resizing. A media HEAD with the required Referer returned `200 video/mp4` with byte-range support; no episode download task was created. No application crash appeared in the smoke-run crash buffer.

Eleven Compose/Espresso cases remain unavailable because of the API 37 `InputManager.getInstance` incompatibility. This migration was not rerun on API 29 or physical devices and does not claim physical performance gains, a full TalkBack walkthrough, or replay of an old app version's implicit Compose saved-state bundle. Explicit persistent schema, preferences, route names, and legacy ViewModel owner keys are preserved; same-version recreation is tested. Prettier, local documentation links, and diff whitespace checks passed. Web business source was unchanged. Disposable emulator display/theme/keyboard preferences were restored afterward.

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
