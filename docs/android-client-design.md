# Android Client Design

Status: Implemented under `android/`. The native page framework was revised at the user's request on 2026-10-08.

Prepared on 2026-10-07. This document owns the Android product, architecture, and acceptance criteria. Build, test, and platform limitations are maintained in the [Android README](../android/README.md). Existing Web contracts remain in [Architecture](architecture.md) and [Upstream API](upstream-api.md).

## Confirmed Brief

Build a production Android client for `sctv-dl` using Kotlin and Jetpack Compose. The first release covers the existing programme catalogue, search, favourites, broadcast dates, full episodes and clips, online playback, quality selection, and download management. It connects directly to the public upstream services and requires no separately deployed Node service.

The client should feel complete on a phone: deliberate visual hierarchy, accessible controls, reliable navigation, durable preferences, meaningful loading and failure feedback, and actual download status. Documentation, comments, and test names remain English; product copy and programme names remain Chinese.

The following design decisions are included in the approved baseline:

- Add the native project under `android/` in this repository.
- Support Android 10 and newer (`minSdk = 29`). Compile and target the current stable Android 17 platform, API 37; avoid preview SDK extensions.
- Use `sctv-dl` as the project identity and `蜀台回看` as the Chinese application label.
- Save downloadable MP4 files in the public Downloads directory through the Android platform download service.
- Keep all account-free data local. No login, cloud synchronization, analytics, recommendations service, TV client, or background audio in the first release.

## Options and Decision

| Approach                                                                            | Benefits                                                      | Costs                                                                    | Decision                      |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------- |
| Compose with ViewModel, repositories, and a few focused modules                     | Native UX, testable state and business rules, clear ownership | Requires Android-specific persistence and media integration              | Recommended                   |
| Compose with every feature split into API, implementation, domain, and data modules | Strong isolation for a large team                             | Adds considerable build and abstraction overhead for the current product | Defer until scale requires it |
| WebView or a hybrid wrapper                                                         | Reuses existing pages                                         | Does not meet the requested native Compose product experience            | Excluded by the brief         |

For downloads, choose `android.app.DownloadManager` for the first release. It transfers ordinary MP4 files into public Downloads and owns background execution, network recovery, and system notifications. The client adds a persistent task index and an accurate management UI. Media3 remains the playback engine.

Media3's separate download manager is a credible alternative when app-private offline media, explicit pause/resume, and cache management become requirements. It would also need file export and foreground-service lifecycle design. A custom transfer engine would need additional resumability and background-execution work. Neither is necessary for the agreed first-release scope.

## Product Structure

### Navigation

Use three primary destinations: `节目库`, `下载`, and `设置`. Catalogue and favourites are the `全部栏目` and `我的收藏` tabs inside the programme library, each retaining its own search, sort, and scroll state. Programme details and playback are secondary destinations. Return navigation restores the originating programme and broadcast date. Back from a primary download or settings page returns to the library before leaving the application.

Compact windows show bottom navigation only on primary destinations; programme details and playback use the full content area with their own return action. Medium and expanded windows use an adaptive navigation rail, except during playback. Expanded archive layouts show the library alongside programme details; switching window size does not lose selection or player position. Download notifications open the download list and are consumed once so recreation does not override subsequent navigation.

### Programme Catalogue

- A compact native app bar combines a television logo, `sctv-dl`, `电视节目下载`, and a search action. Search expands inside the toolbar above the library tabs; opening it explicitly focuses the input. The IME search action dismisses the keyboard, while exiting search clears the current scope's query and restores the brand. Restored queries remain visible without automatically opening the keyboard. The two library tabs identify the current browsing scope. The result count, sorting, and cards form one scrolling content area, leaving the page navigation reachable while browsing.
- Check for updates automatically when the library destination becomes interactive, including return navigation and app resume. Remove pull gestures and accessibility refresh actions. Retain the displayed cached snapshot without a loading indicator. If successful data differs, show an update icon with a theme-coloured dot in the toolbar, labelled `有新内容，点击更新` for accessibility. Its appearance does not move the scrolling content. Accepting it uses the latest cached result and returns the list to its beginning. Unchanged results and timestamps alone do not show the action. Preserve filters and reject duplicate active requests; error and empty-state retries remain available. Returning to a retained destination does not accept pending results.
- Before the first catalogue response, retain the real toolbar and tabs and reserve the exploration, summary, and adaptive grid structure with noninteractive skeletons. Use Compose Shimmer for the subtle placeholder effect and static themed blocks when system animations are disabled. Announce loading once rather than exposing individual placeholders as programmes. Cached refresh keeps real cards and exploration unchanged until acceptance; a successful empty response or initial failure replaces the skeleton with the appropriate state.
- Use an adaptive two-column cover grid on typical phones, a single column when large text requires it, and additional columns when space permits. Cards show a 16:9 cover, the programme name, and an accessible favourite control. Keep the title panel compact: wrap up to two lines only when needed, without a reserved empty line or repeated caption. Card skeletons use the same compact cover/title structure.
- Provide default service order and name order. Favourites precede non-favourites in either mode; preserve ordering within each group.
- The favourites tab reuses the same card, search, and ordering rules. Its empty state explains how to save a programme and provides an action to browse all programmes.
- Do not add invented categories, rankings, durations, audience counts, or programme freshness badges. The current catalogue provides none of those fields.
- The unfiltered all-programmes page includes a compact `栏目探索` card using a real catalogue name and cover. Keep the scrolling header's identity stable during initial loading so the exploration remains visible when metadata arrives. `查看节目` opens that programme; `换一个` randomly selects a different available programme and is disabled when only one exists. Preserve the choice across refresh/recreation while its ID remains available, and use refreshed metadata. Hide exploration in search results, favourites, and embedded archive panes. There is no timed carousel, extra catalogue request, fabricated recommendation label, or autoplay.
- Adapt the brand and exploration to the native layout: a larger adaptive cover in a lightly tilted themed frame with labelled touch actions on phones, more artwork space in wide windows, and text-first layouts at large font scales. Reserve space around the rotation and mirror the frame in loading skeletons. Keep both modules in the library rather than copying the Web sidebar or decorative desktop hero.

### Programme Archive

The archive uses a compact app bar and a scrolling programme header with a 16:9 cover aligned with the full programme name and a favourite action directly below it. Omit a repeated replay subtitle and keep the header compact; its skeleton reserves the same title and favourite structure. Refresh its dates and selected broadcast automatically when the destination becomes interactive, without a pull gesture. Keep cached dates, the selected broadcast, programme metadata, and content stable with no loading indicator. Changed data uses the same toolbar update action as the library; returning from playback or app resume does not accept pending results. Hide the action during batch selection and reject acceptance while selection is active. Before dates or contents are available, show noninteractive skeletons for the unknown header, date shortcuts, broadcast heading, full-episode card, and clip rows. Use Compose Shimmer with the same reduced-animation fallback and one loading announcement as the library. Switching to an uncached broadcast uses content skeletons while keeping known dates and programme context. Combine date/content errors into one page-level retry action, including cached empty results. Recent returned broadcast dates appear in a horizontal row, newest first, and switch directly without opening a sheet. `更多日期` opens the month-grouped date sheet. A date selected from that sheet remains visible in the shortcut row even outside the seven recent broadcasts. Days without an upstream date record are unavailable.

Distinguish a confirmed full episode from individual clips using the existing title-matching rule. Show full episodes prominently when present, while retaining the service's content order within each group. Do not label the first row as a full episode by position.

The content heading displays the selected broadcast date directly, followed by separate full-episode and clip counts. Each available item is one labelled card that opens its playback destination from any point, including the title or cover. A decorative play mark on the cover communicates the action; there are no separate play/download buttons in the archive. Large text uses a text-first clip row with a small play mark. A `批量下载` action enters batch selection mode, replacing the programme/date header with a selection app bar, `全选`, `仅完整节目`, a selected count, and a fixed bottom download action. Full episodes and clips share a compact selection layout with a leading checkbox; the whole card is one labelled toggle target. Back first exits selection mode. Selection clears when the programme or date changes. Items without media remain readable and display `暂未提供视频`; they cannot be selected or played.

Selecting download opens a quality sheet. Show only meaningful available choices for one item. For a batch, show the selected count and explain that items missing the chosen variant use their available variant. Dismissing the sheet creates no tasks. After submission, show the actual queued, fallback, and failed counts, with a route to Downloads.

### Player

Use a dedicated playback destination with a 16:9 video surface, programme and broadcast context, and native Compose controls backed by Media3. Pass the accepted archive item and context in memory when opening playback; validate its programme/date/content key. Pin the playable source and download metadata for that destination so repository updates cannot replace the item being watched. Restored destinations resolve their string IDs from the cache; full metadata is not saved in navigation state. Fullscreen hides the surrounding app chrome and respects system insets.

Below the video and playback controls, show the complete content title, programme name, and broadcast date. A primary `下载节目` button follows this context and opens the existing quality sheet; cap its width in wide windows and keep it reachable by scrolling in short windows or at large text scales. Dismissal creates no task. Downloads remain available if video playback fails while valid variants are present. Local playback has no download action. Fullscreen and picture-in-picture hide the surrounding information and download entry.

Controls include play/pause, seeking, elapsed and total time, fullscreen, playback speed, and the actual available quality variants. Start paused. Read the saved quality preference for initial selection. A quality change retains the player instance, position, and prior playing state. If source replacement fails, present a retry action and preserve the intended position.

Offer Picture-in-Picture as an explicit action where supported. Ordinary backgrounding pauses playback; Picture-in-Picture continues it. Audio focus loss and becoming noisy follow Media3 behaviour. Back exits fullscreen before leaving playback.

Player ownership is scoped to the playback destination, rather than a reusable card or an application singleton. Pause when dismissal is committed; release once the outgoing transition finishes. A cancelled predictive-back gesture must not prematurely destroy playback. A late callback from an outgoing destination cannot clear a newly opened one.

Opening a completed download reads its content URI locally and works without network access. If the file has been removed outside the app, show a missing-file state with a route to re-download.

### Download Management

Use `进行中` and `已完成` sections. Failed or interrupted tasks remain visible in the first section with a specific reason and a retry action. An empty download page explains how to download a programme.

| State     | Display                                                  | Available actions                        |
| --------- | -------------------------------------------------------- | ---------------------------------------- |
| Preparing | Validating media and resolving the actual quality        | Cancel preparation                       |
| Pending   | Waiting for the Android download service                 | Cancel                                   |
| Running   | Actual bytes downloaded, total and percentage when known | Cancel                                   |
| Waiting   | Actual system reason, such as waiting for Wi-Fi or retry | Cancel; open relevant system settings    |
| Failed    | Specific HTTP, storage, or resume error                  | Retry; remove record                     |
| Completed | Actual filename, size when known, and location           | Play locally; open; share; remove record |
| Cancelled | Explicit cancellation result                             | Retry; remove record                     |
| Missing   | Previously completed file is no longer accessible        | Re-download; remove record               |

Unknown content length uses an indeterminate indicator and actual received bytes. Do not fabricate percentage, speed, completion, or estimated remaining time. No manual pause/resume controls are shown because the platform API does not expose them. System-managed waiting and recovery are displayed truthfully.

`Remove record` removes application history and leaves a completed MP4 in Downloads. `Cancel` stops an active system download and may remove its partial file. Clearly label these different actions. Completed files remain accessible through the system file manager after application removal.

The default network policy permits ordinary connected networks. Offer `仅 Wi-Fi 下载` as a saved preference applied to new tasks; each queued task shows its effective network policy. Changing the preference does not silently cancel and recreate existing jobs. A quality preference controls initial playback, while each download still chooses its own quality.

### Settings

Use a primary settings page with separate surface groups for appearance, playback, downloads, and app information. Provide `跟随系统 / 浅色 / 深色`, an optional system dynamic-colour setting, the initial playback quality, and the Wi-Fi-only download preference. The theme defaults to following the system; dynamic colour defaults off to preserve the product palette.

Do not require onboarding, account registration, notification permission, or broad storage permissions merely to browse programmes. Request any future capability-specific permission at the action that needs it.

## Visual and Interaction System

Use stable Material 3 components and a custom theme. The default palette uses a restrained warm vermilion accent, cool neutral backgrounds with white panels in light mode, and graphite backgrounds with charcoal panels in dark mode. Define semantic roles for background, surface, primary action, text, outline, error, and completed status; do not scatter literal colours through feature screens.

| Token          | Value or rule                                                                        |
| -------------- | ------------------------------------------------------------------------------------ |
| Primary        | Light: `#AD3D28`; dark: `#FFB4A4`, with paired accessible foregrounds                |
| Background     | Light: `#F6F7F9`; dark: `#16191E`                                                    |
| Surface        | Light: `#FFFFFF`; dark: `#1E2229`                                                    |
| Main text      | Light: `#242A33`; dark: `#E7E9EE`                                                    |
| Secondary text | Light: `#667080`; dark: `#A9AEB8`                                                    |
| Spacing        | 4dp base; 16dp compact page padding; 12dp grid gaps                                  |
| Shape          | 16dp programme cards; 12dp content panels; native control and sheet roles            |
| Typography     | System sans-serif with native Chinese fallback; Material type roles in sp            |
| Targets        | At least 48dp for interactive controls                                               |
| Motion         | Short purposeful state and navigation transitions; respect system animation settings |

Favour compact editorial layouts and real programme artwork. Use restrained borders and elevation, and reserve strong filled actions for the screen's main action. Avoid decorative dashboards and excessive chips. Long Chinese titles wrap and remain inspectable; button labels must not be squeezed into icon-only controls.

Cover images use deterministic aspect ratios, a neutral placeholder, and a graceful failure state. Programme cards and video content are different reusable components rather than one overloaded card.

Support edge-to-edge rendering, display cutouts, gesture navigation, keyboard insets, TalkBack, sufficient text contrast, and font scale up to 200%. Progress and favourite state have spoken labels. Selection is indicated with text or check state as well as colour. Avoid duplicate accessibility announcements from decorative cover images.

Every data screen distinguishes initial loading, successful content, genuinely empty data, empty search results, cached data while refreshing, refresh failure, and unrecoverable initial failure. Cached catalogue and archive records are usable offline, but uncached online media clearly requires connectivity.

## Kotlin and Compose Architecture

Use one Activity and a saved, typed Navigation 3 back stack. Screen-level ViewModels expose immutable `StateFlow<ScreenUiState>` values and receive named user actions. Compose screens collect through `collectAsStateWithLifecycle`; leaf components receive values and callbacks. Durable outcomes belong in state instead of fire-and-forget event channels.

ViewModels depend on repository contracts and do not own Activity, Context, database objects, Retrofit services, download cursors, or ExoPlayer instances. Constructor injection uses Hilt. Pure domain functions cover quality fallback, full-episode recognition, ordering, ID validation, and safe filenames.

Use a few modules with explicit ownership:

| Module         | Owns                                                                                                                 | Dependencies                                    |
| -------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `:app`         | Activity, navigation, DI wiring, catalogue/archive/favourites/downloads/settings feature packages, screen ViewModels | Core modules                                    |
| `:core:domain` | Domain models, repository contracts, typed errors, pure business policies                                            | Kotlin and coroutines; no Android UI or storage |
| `:core:data`   | Retrofit API, DTO parsing, Room, DataStore, platform download adapter, repository implementations                    | Domain; Android data libraries                  |
| `:core:design` | Material theme, tokens, shared media cards and state feedback                                                        | Compose and Material 3                          |
| `:core:player` | Media3 controller, video surface, Compose playback controls and lifecycle integration                                | Domain; Media3; Compose                         |

Feature packages do not import each other's implementation. Shared modules never depend on feature ViewModels. Introduce a reusable use case only when multiple screens need the operation or a workflow requires coordination; avoid a pass-through class for every repository method.

Use Retrofit with OkHttp and kotlinx.serialization, Room for the metadata/task index, DataStore for preferences, and Coil for covers. Use the Media3 Compose UI APIs for playback. Keep Gradle configuration in Kotlin DSL, centralize exact dependency versions in a version catalogue, use a verified Gradle wrapper, and pin a mutually compatible stable toolchain. Compose artifacts use the stable BOM; independently versioned libraries are pinned explicitly. Do not adopt alpha dependencies simply because a documentation snippet lists them.

Kotlin code follows the official style: four spaces, meaningful PascalCase source files and types, lowerCamelCase functions and properties, and grouped related declarations. Unit-returning composables use PascalCase and accept a `Modifier` parameter where applicable. Prefer `val`, private mutable state, sealed error/state types, and explicit public contracts. Avoid `!!`, `GlobalScope`, blanket exception suppression, and Android references in pure business code.

Inject coroutine dispatchers at boundaries that perform blocking work. Keep repository operations main-safe. Rethrow `CancellationException`; handle expected failures explicitly. Use scoped coroutines, `flatMapLatest` for changing archive selections, and keyed responses to reject obsolete commits even when cancellation is late. Pass identifiers through navigation rather than complete mutable models.

## Data and Native Transport

### Boundary Contract

Retain the current business contracts:

- Request only catalogue page 0 with size 100, dates for a validated programme ID, and contents for its returned date record ID.
- Require an envelope with `rs = 200` and the expected payload shape. Report HTTP, non-JSON, business, and validation failures separately.
- Keep IDs as digit strings. Preserve arbitrarily large string IDs exactly. Numeric JSON IDs must be non-negative integers no greater than the Web contract's safe-integer limit; do not parse through `Double`.
- Parse broadcast dates as valid ISO calendar dates, retain the last returned record per date, and sort newest first.
- Normalize missing optional media and cover fields. Preserve `video` as standard and `videoStandard` as smooth.
- Resolve relative media against `https://fscgc.scgchc.com/` and relative covers against `https://kscgc.sctv.com/`.
- Require initial media targets to be credential-free HTTPS MP4 URLs on `fscgc.scgchc.com` with the default port. Never accept arbitrary user-entered media URLs.
- Allow HTTPS cover hosts observed in the existing service: `kscgc.sctv.com`, `kscgc.scgchc.com`, and `kscgc.sctv-tf.com`. Unrecognized covers use the fallback rather than weakening media validation.
- Send `Referer: https://scgc.video.play/` for native playback, media preflight, and download requests. Metadata requests do not require a browser CORS proxy.
- Disable redirects in application-controlled API and media clients. Android's platform download service owns its transfer redirect handling; do not claim the app can impose the Node proxy's redirect policy on it.
- Deduplicate identical video URLs. Resolve fallback explicitly and name files using the actual downloaded quality.

The existing Web and Node proxy remain unchanged. These Android transport decisions do not relax the server's restrictions.

### Persistence and Refresh

Room holds programme records, date records keyed by programme, content records keyed by programme and date, favourites, and a local download index. Store successful empty archive responses as fetched results rather than treating an empty table as an unfetched request. A successful refresh replaces only the relevant cached snapshot in a transaction; a failed request preserves its last successful snapshot.

The repository exposes cache-backed flows with an explicit refresh state. Refresh the catalogue and the selected programme/date on destination entry while presenting their cache. ViewModels keep the displayed snapshot separate from the newest repository result; initial data appears immediately, but later successful differences require explicit acceptance, including a changed or empty response. Apply dates before contents, discard pending rows when their programme/date key changes, and retain errors without inventing content updates. Retry actions request data without automatically accepting pending changes. Do not fetch every programme's archive in the background. Cross-key isolation ensures a date change cannot render another date's contents while a new request is loading.

Use `SavedStateHandle` and saved navigation state for selected IDs, query, and selection-mode state. Restore only content IDs that still exist for the restored archive key. Native preferences have their own versioned schema and safe defaults; browser localStorage remains untouched, with no implied cross-platform synchronization.

### Download Consistency

Before enqueueing, persist the task identity, requested/actual quality, source URL, network policy, and a unique safe planned filename. Perform a cancellable HEAD media preflight. If HEAD is unsupported, use a small Range request and close it after headers or bounded bytes; never buffer the complete video.

Enqueue through the system service, persist its system ID, and derive transfer state from queries. Query active tasks while Downloads is visible and reconcile on app start, foreground entry, and download completion. A broadcast is a reason to query, never proof of successful completion.

The task identity includes the content ID, actual quality, and normalized URL. A transaction prevents duplicate active submissions. A crashed enqueue is recovered by matching the persisted unique destination against the app's own system downloads before allowing a retry. Never resubmit an ambiguous task automatically. Failed members of a batch do not stop successful members.

Use content URIs for open, share, and local playback, with temporary read grants when handing files to another app. Recheck availability instead of trusting a saved path. Remove stale platform IDs during restore to another device; do not back up runtime transfer IDs as resumable jobs. Wi-Fi constraints and retry reasons come from the system service.

## Verification and Release Criteria

The following checks are acceptance requirements for implementation, not claims of completed verification:

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

Android unit tests live in the standard `src/test` source sets, and device/UI tests in `src/androidTest`. Use fakes and stub upstream responses rather than live services in automated tests. Existing TypeScript tests retain their current locations and conventions.

Expose actual Android verification commands in `android/README.md` when the project is implemented. Keep SDK paths, Gradle caches, emulator state, signing keys, and generated build products out of Git. Generated baseline profile rules are portable source inputs, reviewed with changes to the critical journeys. The release signing identity and any store submission remain separate delivery steps; do not present a debug APK as a signed production release.

## Research and Current Evidence

Official guidance checked on 2026-10-07:

- [Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations): UI/data separation, repositories, unidirectional state, lifecycle-aware collection, ViewModels, and DI.
- [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html): source organization, naming, formatting, and Compose naming.
- [Android coroutine practices](https://developer.android.com/kotlin/coroutines/coroutines-best-practices): immutable state, main-safe operations, scoped work, and cancellation.
- [Navigation 3 releases](https://developer.android.com/jetpack/androidx/releases/navigation3): Compose-native navigation has a stable release; use the stable line.
- [Adaptive navigation](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation): navigation changes with the window rather than the device label.
- [Compose accessibility defaults](https://developer.android.com/develop/ui/compose/accessibility/api-defaults): semantic interaction and minimum touch targets.
- [Media3 Compose UI](https://developer.android.com/media/media3/ui/compose): native Compose video surfaces and control state.
- [Platform DownloadManager](https://developer.android.com/reference/android/app/DownloadManager) and [DownloadManager.Request](https://developer.android.com/reference/android/app/DownloadManager.Request): system transfers, status/byte queries, destination and network controls.
- [Background data transfer choices](https://developer.android.com/develop/background-work/background-tasks/data-transfer-options) and [Media3 media downloads](https://developer.android.com/media/media3/exoplayer/downloading-media): alternative transfer strategies and lifecycle costs.
- [Android 17](https://developer.android.com/about/versions/17): current stable platform and behaviour-change verification.

Live checks on the same date returned a successful catalogue, dates for programme `1`, and content for broadcast `2026-10-06`. Its date ID was `2107420533961056258`, demonstrating why IDs must remain strings. One MP4 probe with the required Referer and `Range: bytes=0-15` returned HTTP 206, `video/mp4`, and a 16-byte range of a 562,454,394-byte resource. The response was closed without downloading the complete video. This validates one native-access path, not all programme media or Android player behaviour.

The implemented client, setup commands, performance harnesses, and runtime limitations are documented in the [Android README](../android/README.md). Device and release verification use separate runs; workstation resource controls remain transient rather than tracked defaults.
