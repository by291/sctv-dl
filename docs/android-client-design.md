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

New downloads use Media3's native progressive downloader, persisted private cache/index, constrained JobScheduler recovery and explicit foreground-service execution. The application owns attempt identity, network permission, publication and user actions. Version-1 DownloadManager tasks retain their platform ownership and capabilities. No custom MP4 transfer loop is introduced.

## Product Structure

### Navigation

Use three primary destinations: `节目库`, `下载`, and `设置`. The library heart toggle filters the cards on the current page, keeping the exploration header, search, sort and grid controller in place. Programme details and playback are secondary destinations. Return navigation restores the originating programme and broadcast date. Back from a primary download or settings page returns to the library before leaving the application.

Primary pages share one app-bar component with a 64 dp content height, increasing to 88 dp at font scales of 150% or greater. Status-bar insets are separate. Search keeps the same height as the library brand, so opening it or switching primary pages preserves the toolbar alignment.

Compact windows show bottom navigation only on primary destinations; programme details and playback use the full content area with their own return action. Medium and expanded windows use an adaptive navigation rail, except during playback. Expanded archive layouts show the library alongside programme details; switching window size does not lose selection or player position. Download notifications open the download list and are consumed once so recreation does not override subsequent navigation.

Bottom navigation retains each primary entry's reserved spacing until that entry leaves composition. The bars share one namespaced native shared-element key with identical bounds, keeping a single visual at rest during primary changes while content moves independently. Both bars keep their normal appearance while their controls and accessibility actions wait for the native transition to settle. Interaction follows the scene lifecycle and native back-gesture state, so cancelling a preview restores tab actions without depending on child visibility-animation completion. Returning to a retained secondary catalogue destination has no matching bar, so the outgoing bar leaves with its primary entry. Opening programme details never expands the outgoing library into the disappearing navigation area. The shared-transition viewport itself is clipped, including its overlay.

Primary destination changes follow a 250 ms sequence: a 90 ms fade/20 dp exit, followed by a 160 ms fade/20 dp entry. Ordinary secondary pushes use 30 dp shared-axis motion with fade-through over 300 ms; ordinary pops reverse the direction. Navigation 3 seeks the same pop transform for predictive back, with the physical gesture edge determining its direction. Pages remain full-size throughout. The system owns return-to-home; app-level back callbacks only consume an actual in-app return. These timings belong to navigation and shared presentation, not a global animation setting, and system animation settings remain respected.

Opening a catalogue card or exploration programme shares its cover with the archive header through Compose's native shared-element transition. Page and shared-cover bounds use the same 300 ms duration and easing, including predictive seeking, cancellation, and commit settling. Exploration artwork rotates upright while moving into the header; its rotation follows the actual animated bounds. Grid covers remain upright. Only the clicked source participates, even when the same programme appears in both places; the embedded library does not introduce a third match. The programme ID and cover URL identify the image, and returning restores the original browsing position. Missing covers, absent source items, and large-text archives without artwork use the ordinary page transition. The shared layer owns image motion rather than inheriting a second page-scale animation. Cancelling a gesture preserves the current entry and player; dismissal callbacks run only when back commits, and player disposal still waits for the leave transition. Search, batch selection, and fullscreen consume back to close their local state before leaving the page.

The archive header previews the accepted catalogue programme during entry, before the destination starts its normal refresh. Opening the archive retains that programme snapshot; newer names or artwork remain pending until the user accepts the existing update action. Dates, contents, and playback keep their existing cache and lifecycle contracts.

### Programme Catalogue

- A compact native app bar combines a television logo, single-line `sctv-dl` brand, and a search action. Search expands inside the toolbar above the scrolling catalogue; opening it explicitly focuses the input. The IME search action dismisses the keyboard, while exiting search clears the current scope's query and restores the brand. Restored queries remain visible without automatically opening the keyboard. The heart toggle beside the result count identifies the current browsing scope. The result count, sorting, and cards form one scrolling content area, leaving the page navigation reachable while browsing.
- Check for updates automatically when the library destination becomes interactive, including return navigation and app resume. Remove pull gestures and accessibility refresh actions. Retain the displayed cached snapshot without a loading indicator. If successful data differs, show an update icon with a theme-coloured dot in the toolbar, labelled `有新内容，点击更新` for accessibility. Its appearance does not move the scrolling content. Accepting it uses the latest cached result and returns the list to its beginning. Unchanged results and timestamps alone do not show the action. Preserve filters and reject duplicate active requests; error and empty-state retries remain available. Returning to a retained destination does not accept pending results.
- Before the first catalogue response, retain the real toolbar and reserve the exploration, summary, and adaptive grid structure with noninteractive skeletons. Use Compose Shimmer for the subtle placeholder effect and static themed blocks when system animations are disabled. Announce loading once rather than exposing individual placeholders as programmes. Cached refresh keeps real cards and exploration unchanged until acceptance; a successful empty response or initial failure replaces the skeleton with the appropriate state.
- Use an adaptive two-column cover grid on typical phones, a single column when large text requires it, and additional columns when space permits. Cards show a 16:9 cover, the programme name, and a 32 dp favourite control with a 20 dp icon. Its hit area matches its visible bounds rather than expanding into the surrounding cover. Keep the title panel compact: wrap up to two lines only when needed, without a reserved empty line or repeated caption. Card skeletons use the same compact cover/title structure.
- Provide default service order and name order, using service order to break equal-name ties. Favourites precede non-favourites in either mode using the favourite IDs first loaded at application startup. Keep that grouping for the retained library's lifetime: saving or removing a favourite immediately updates its heart and membership in the favourites filter without moving cards or resetting the scroll position. Returning from programme details, switching pages, resuming from the background, and refreshing or accepting metadata updates preserve this grouping. Restarting the application applies the latest favourites; explicit sort changes still order rows within the startup groups.
- Place a heart toggle beside the catalogue count and before sorting, matching the Flutter library. Its selected state filters only the cards below the header; toggling it preserves the current query, ordering, exploration and page position. Existing saved filter keys remain readable, with the active controls carried across a toggle.
- The favourites filter reuses the same card, search, and ordering rules. Its empty state explains how to save a programme and provides an action to browse all programmes.
- Do not add invented categories, rankings, durations, audience counts, or programme freshness badges. The current catalogue provides none of those fields.
- The library includes a compact `栏目探索` card using a real catalogue name and cover. Keep the scrolling header's identity stable during initial loading so the exploration remains visible when metadata arrives. `查看节目` opens that programme; `换一个` randomly selects a different available programme and is disabled when only one exists. Preserve the choice across refresh/recreation while its ID remains available, and use refreshed metadata. Hide exploration in search results and embedded archive panes; favourite filtering leaves it unchanged. There is no timed carousel, extra catalogue request, fabricated recommendation label, or autoplay.
- Adapt the brand and exploration to the native layout: a larger adaptive cover in a lightly tilted themed frame with labelled touch actions on phones, more artwork space in wide windows, and text-first layouts at large font scales. Reserve space around the rotation and mirror the frame in loading skeletons. Keep both modules in the library rather than copying the Web sidebar or decorative desktop hero.

### Programme Archive

The archive uses a compact image-and-text header beneath its ordinary app bar. Artwork takes 52–54% of the row after spacing, capped at 256 dp, and keeps its 16:9 ratio and rounded corners. Place the full programme title above a plain favourite text button beside the image; retain the heart icon, 48 dp minimum touch target, and favourite-state label without a filled background. Titles wrap naturally. At font scales of 150% or greater, use the full width for the name and action. The header scrolls with the content, and navigation retains the list position. Selection mode replaces the header with its existing selection controls. Loading placeholders use the same header layout and reserve its title and favourite-action space. Refresh its dates and selected broadcast automatically when the destination becomes interactive, without a pull gesture. Keep cached dates, the selected broadcast, programme metadata, and content stable with no loading indicator. Changed data uses the same toolbar update action as the library; returning from playback or app resume does not accept pending results. Hide the action during batch selection and reject acceptance while selection is active. Before dates or contents are available, show noninteractive skeletons for the unknown header, date shortcuts, broadcast heading, full-episode card, and clip rows. Use Compose Shimmer with the same reduced-animation fallback and one loading announcement as the library. Switching to an uncached broadcast uses content skeletons while keeping known dates and programme context. Combine date/content errors into one page-level retry action, including cached empty results. Recent returned broadcast dates appear in a horizontal row, newest first, and switch directly without opening a sheet. `更多日期` opens the month-grouped date sheet. A date selected from that sheet remains visible in the shortcut row even outside the seven recent broadcasts. Days without an upstream date record are unavailable.

The date sheet presents inset month groups with actual broadcast-day counts. Highlight the selected date and make each whole row one accessible single-selection action; selecting a date closes the sheet.

Distinguish a confirmed full episode from individual clips using the existing title-matching rule. Show full episodes prominently when present, retaining service order among full episodes. Do not label the first row as a full episode by position.

The content heading displays the selected broadcast date directly, followed by separate full-episode and clip counts. Each available item is one labelled card that opens its playback destination from any point, including the title or cover. A decorative play mark on the cover communicates the action; there are no separate play/download buttons in the archive. Large text uses a text-first clip row with a small play mark. A `批量下载` action enters batch selection mode, replacing the programme/date header with a selection app bar, `全选`, `仅完整节目`, a selected count, and a fixed bottom download action. Full episodes and clips share a compact selection layout with a leading checkbox; the whole card is one labelled toggle target. Back first exits selection mode. Selection clears when the programme or date changes. Items without media remain readable and display `暂未提供视频`; they cannot be selected or played.

Archive card titles wrap to at most two lines at ordinary text sizes, with an ellipsis for overflow. Large text retains up to six lines and the existing text-first clip layout.

Clip cards show the upstream publication time below their title, retaining seconds. Include the full date when publication differs from the selected broadcast date; missing or invalid publication text shows an unknown-time label. Full-episode cards do not display publication time. Order clips chronologically by default, with a single sorting icon button at the clip heading toggling ascending/descending order. The three bar lengths grow from top to bottom in ascending order and shrink in descending order. Equal timestamps retain upstream order, and unknown timestamps remain last in both directions. Store the direction in archive saved state, retain it across date changes and return navigation, and reset it for another programme. Disable sorting during batch selection to keep the presented rows stable. Sorting applies only to accepted contents and does not accept pending repository updates.

Selecting download opens a quality sheet. Show only meaningful available choices for one item. For a batch, show the selected count and explain that items missing the chosen variant use their available variant. Dismissing the sheet creates no tasks. After submission, show the actual queued, fallback, and failed counts, with a route to Downloads.

### Player

Use a dedicated playback destination with a 16:9 video surface, programme and broadcast context, and native Compose controls backed by Media3. Pass the accepted archive item and context in memory when opening playback; validate its programme/date/content key. Pin the playable source and download metadata for that destination so repository updates cannot replace the item being watched. Restored destinations resolve their string IDs from the cache; full metadata is not saved in navigation state. Fullscreen hides the surrounding app chrome and respects system insets.

An archive cover and player artwork share the accepted programme/date/content identity and image URL. Mount the final player page and accepted artwork immediately while playback history and settings load. Keep the same player, artwork node and video bounds when preparation completes; do not show an intermediate loading page. Load media using the restored position and quality only when prepared, and do not persist the unprepared player position. Only fully visible source images participate; preserve their eligibility while the archive is retained. Keep the native video at its final geometry beneath the shared artwork. Wait for route entry and the first decoded frame before fading artwork over 120 ms, and keep it mounted for return transitions. Incoming archive artwork fades in during the first 35% of the page transition to complement the departing video. Fullscreen, PiP and missing artwork use ordinary navigation.

Below the video, show the complete content title, programme name, and broadcast date. A primary `下载节目` button follows this context and opens the existing quality sheet. Align the title and button within the same content column, capped at 720 dp in wide windows, and keep them reachable by scrolling in short windows or at large text scales. Dismissal creates no task. Downloads remain available if video playback fails while valid variants are present. Local playback has no download action. Fullscreen and picture-in-picture hide the surrounding information and download entry.

Controls overlay the video. Route play/pause and seek through the controller and use a native Material3 slider. Place play, elapsed time, seek, duration, speed, actual quality and fullscreen in one compact bottom row with stable tabular, hour-aware time widths and 48 dp touch targets. Time, speed and quality share label-medium typography and vertical alignment. Use compact menu slots, a rounded 3 dp track, and a 4 by 9 dp indicator with no gap in the track. Allow horizontal scrolling when large text or a narrow window needs it; explicit PiP sits at the upper right without a filled button background. Speed and quality choices open upward from their controls in a vertical translucent neutral menu with theme accent text for the current option. Reserve space for every speed label at the current text scale so changing speed does not move the menu anchor. Constrain its height to the video and scroll overflowing options; outside taps and Back dismiss it without changing the selection. Keep controls visible while paused, buffering, in error, focused, seeking, or choosing a menu item. Hide playing controls after 3.5 seconds of inactivity, respecting the system accessibility timeout; tapping the video reveals them again. Unknown duration remains `--:--`. Short and large-text windows reserve enough video height to keep these controls reachable. Start paused. Read the saved quality preference for initial selection. A quality change commits after readiness and retains the player instance, position and speed. A failed switch rolls back once to the last usable source; a later pause or external transport command wins over the captured intent. Failed restoration retains explicit retry context. Ended playback restarts on the first play press.

Blank video supports single-tap controls, double-tap playback, and horizontal seek preview with one commit on release. A full-width drag spans the smaller of the duration and 120 seconds (a quarter-width drag advances 25 seconds in a 100-second clip and 30 seconds in an hour-long episode), clamped to the available timeline. Unknown duration disables seeking. Long press while playing temporarily uses 2×, preserving the selected speed across release, cancellation, quality/retry, rotation, background, PiP and exit. Fullscreen vertical drags adjust window brightness on the left and system media volume on the right, with a concise HUD. Brightness restores when fullscreen ends or playback backgrounds; volume remains the user's setting and each update reads the native level to respect physical keys. Gesture recognition excludes a 24 dp surface edge, uses touch slop and direction locking, cancels on multiple pointers or lifecycle changes, and sits behind interactive controls. A non-consuming video ancestor observes pointers on both the blank layer and real controls. Inline vertical movement remains available to page scrolling. Touch exploration disables surface gestures while labelled controls remain available. The fullscreen gesture hint requires a resumed Activity and focused window. Only the user’s explicit acknowledgement persists the local seen flag; window/lifecycle interruptions retain eligibility, including when system immersive onboarding obscures the hint.

Offer Picture-in-Picture as an explicit action where supported. Ordinary backgrounding pauses playback; Picture-in-Picture continues it. Audio focus loss and becoming noisy follow Media3 behaviour. Back exits fullscreen before leaving playback.

Player ownership is scoped to the playback destination, rather than a reusable card or an application singleton. Pause when dismissal is committed; release once the outgoing transition finishes. Fullscreen window changes activate only when the destination reaches `RESUMED`, so a retained-player preview cannot rotate the Activity or hide system bars before back commits. An activated fullscreen window remains intact through the leave animation and resets on disposal. Use a TextureView-backed video surface so decoded pixels follow the outgoing page opacity and transforms throughout the transition. A cancelled predictive-back gesture must restore the visible frame without prematurely destroying playback. A late callback from an outgoing destination cannot clear a newly opened one.

Opening a completed download reads its content URI locally and works without network access. If the file has been removed outside the app, show a missing-file state with a route to re-download.

### Download Management

Provide `全部`, `下载中`, `未完成`, `已完成`, and `文件已移除` filters with independent saved positions. Paused and finalizing tasks remain active. Failed/cancelled tasks are unfinished; missing public files have their own neutral state. Selection stores attempt IDs and clears on filter change. Every batch member is revalidated independently; consent dismissal and per-item failures do not discard successful work.

Managed transfers offer pause/resume, cancel, and retry as their durable state permits. Legacy system tasks never offer unsupported pause controls. Retain actual artwork, full titles, programme/date context and actual quality. Show actual received bytes and known total progress; never fabricate duration, speed, completion or ETA. A failed publication offers `重试保存` using the complete private cache. Public-file deletion retains a missing-file record, while record removal preserves public files and cleans private resources. Destructive actions are explicitly confirmed.

Wi-Fi-only is captured at creation and accepts metered Wi-Fi, excludes Ethernet, and waits under VPN. Unrestricted work respects the active VPN. Existing jobs do not change policy when the preference changes. Foreground and scheduled execution have bounded lifetimes; closing a lease cancels ongoing streaming calls. A visible page alone cannot restart transfers.

### Viewing History and Storage

History stores accepted metadata and exact programme/date/content identity, shared by online and newly downloaded copies. Legacy local videos use task-scoped identity. Keep the newest 500 records with deterministic timestamp ties. Save advancing progress at five-second intervals and flush pause, completed seek, background, completion and route exit. Completed playback, or 95% of a known duration, opens from zero; incomplete content resumes paused. Keep a cover until the correct first frame and show retryable persistence errors without blocking playback.

History is a secondary library destination with search, local-day groups, resume/replay, and individual removal. Back closes search first. FIFO writes plus per-key session/deletion generations prevent obsolete snapshots from resurrecting deleted history. Favourites, history and the transactional import marker live in the separate user database and are eligible for backup with settings. Restored import markers remain authoritative; runtime tasks, caches and public-file references are excluded.

Cache cleanup retires metadata and image generations so in-flight old requests cannot refill the new cache. It only clears programme/date/content snapshots and Coil caches. History clearing is a separate confirmation and preserves downloads. Each cleanup result reports its own failure.

### Settings

Use a primary settings page with separate surface groups for appearance, playback, downloads, storage/history, and app information. Provide `跟随系统 / 浅色 / 深色`, an optional system dynamic-colour setting, the initial playback quality, and the Wi-Fi-only download preference. The theme defaults to following the system; dynamic colour defaults off to preserve the product palette.

Switch rows span the card width, including their horizontal content insets, and retain a single accessible switch action. Their ripple is clipped by the enclosing card shape. Noninteractive preference content owns its own padding.

Changes to light/dark mode or dynamic colour interpolate all Material colour roles over 300 ms through Compose's native colour animation. Keep the current destination, scroll position, focus, and playback content in composition. Interrupted changes continue from the currently displayed colours, and the system animator duration scale controls or disables the transition.

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

The library toolbar and adaptive launcher icon share the `core:design` vector resource `ic_sctv_brand`. The toolbar tints it with the active theme; the launcher uses the white mark on the brand background, inset to a 48dp mark within the 108dp layer so it stays clear of circular masks. Its foreground and monochrome layers use the same inset drawable. Keep the television geometry in that shared resource.

Cover images use deterministic aspect ratios, a neutral placeholder, and a graceful failure state. Programme cards and video content are different reusable components rather than one overloaded card.

Interactive cards use Material's clickable or checked surfaces so press feedback is clipped by the same rounded shape as their content. Whole-card batch selection retains a checkbox role and checked state; nested actions remain independent controls.

Support edge-to-edge rendering, display cutouts, gesture navigation, keyboard insets, TalkBack, sufficient text contrast, and font scale up to 200%. Progress and favourite state have spoken labels. Selection is indicated with text or check state as well as colour. Avoid duplicate accessibility announcements from decorative cover images.

Archive video lists extend beneath the system navigation area. The programme library keeps its viewport above a bottom navigation bar; when navigation uses a rail, its grid and the embedded library pane also extend into the system navigation area. Apply bottom safe spacing as scrollable content padding so the last item can settle fully above navigation. The fixed batch download action keeps its controls above system navigation.

Every data screen distinguishes initial loading, successful content, genuinely empty data, empty search results, cached data while refreshing, refresh failure, and unrecoverable initial failure. Cached catalogue and archive records are usable offline, but uncached online media clearly requires connectivity.

## Kotlin and Compose Architecture

Use one Activity and a saved, typed Navigation 3 back stack. Screen-level ViewModels expose immutable `StateFlow<ScreenUiState>` values and receive named user actions. Compose screens collect through `collectAsStateWithLifecycle`; leaf components receive values and callbacks. Durable outcomes belong in state instead of fire-and-forget event channels.

ViewModels depend on repository contracts and do not own Activity, Context, database objects, Retrofit services, download cursors, or ExoPlayer instances. Constructor injection uses Hilt. Pure domain functions cover quality fallback, full-episode recognition, ordering, ID validation, and safe filenames.

Use feature modules with explicit ownership:

| Module                | Owns                                                                                  | Project dependencies                  |
| --------------------- | ------------------------------------------------------------------------------------- | ------------------------------------- |
| `:app`                | Activity/application, root navigation, global state/reconciliation and playback host  | Core modules and feature entry points |
| `:feature:programmes` | Catalogue/favourites/archive, accepted snapshots, programme/episode UI                | Domain, design, UI                    |
| `:feature:downloads`  | Task list/actions and native open/share handoff                                       | Domain, design, UI                    |
| `:feature:settings`   | Settings screen and preference mutation                                               | Domain, design, UI                    |
| `:feature:player`     | Online/local destination state, source selection and session lifetime                 | Domain, design, UI, player            |
| `:core:domain`        | Subject-organized models, repository contracts and pure policies                      | Kotlin/coroutines; no Android         |
| `:core:data`          | Subject-organized repository implementations, remote/local/platform boundaries and DI | Domain                                |
| `:core:design`        | Generic Material theme/tokens and presentation primitives                             | No project dependencies               |
| `:core:ui`            | Covers/transitions, download sheet/outcomes, cached errors and app theme adapter      | Domain, design                        |
| `:core:player`        | Playback model/controller, Media3 session, video surface and controls                 | Domain                                |

Features expose Route entry points and small immutable selection/host contracts; screens, ViewModels and components remain internal. Features never import sibling features, `app`, or data implementations. Core modules never import features or `app`. The root Gradle `checkModuleDependencies` task validates these edges as part of `check`. Android library, Compose and Hilt convention plugins share defaults without introducing another runtime layer. Shared Kotlin repository fakes live in domain test fixtures and are consumed only by tests; component tests live with their owners and app tests cover root navigation/restoration.

`AppViewModel` observes global preferences and retains download feedback with stable identities and cancellation propagation. Catalogue state remains observed from the root across destination changes so accepted artwork/content does not disappear when an archive opens. `ProgrammeLibraryState` retains the saveable library scroll position for expanded panes across resizing and archive replacement. Individual pane compositions own separate grid controllers so outgoing and incoming entries can coexist during navigation. App navigation maps archive selection into the player's immutable input; it does not pass pending metadata. The player feature binds its session through `PlaybackHost`, implemented by the Activity adapter, and saves position/unbinds/exits fullscreen/releases when the entry is disposed after navigation motion.

Organize source packages by subject and responsibility. Name concrete implementations accurately, including `CachedProgrammeRepository`, `RoomFavouriteRepository`, `ProgrammeResponseParser`, `UpstreamUrlPolicy`, `DownloadManagerRepository`, `DownloadManagerGateway`, and `DownloadEventsReceiver`. Name UI by purpose: `EpisodeCard`, `DownloadQualitySheet`, `OnlinePlayerViewModel`. Keep related small declarations together. Introduce reusable use cases when shared workflows need coordination; simple repository actions can remain direct.

Package moves preserve database filename/version/schema/identity, DataStore filename/keys and enum values, saved filter/selection/position keys and legacy ViewModel owner keys, application ID, backup policy and serialized `AppRoute` names. Update manifest component references and regenerate baseline profiles when class packages move. The checked-in Gradle wrapper is executable on Unix checkouts.

This structure follows the [Android architecture recommendations](https://developer.android.com/topic/architecture/recommendations), [modularization patterns](https://developer.android.com/topic/modularization/patterns), [Navigation 3 modularization guidance](https://developer.android.com/guide/navigation/navigation-3/modularize), and [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html), consulted on 2026-10-10.

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
- Require initial media targets to be credential-free HTTPS MP4 URLs on `fscgc.scgchc.com` or `fscgc.sctv-tf.com` with the default port. Never accept arbitrary user-entered media URLs.
- Allow HTTPS cover hosts observed in the existing service: `kscgc.sctv.com`, `kscgc.scgchc.com`, and `kscgc.sctv-tf.com`. Unrecognized covers use the fallback rather than weakening media validation.
- Send `Referer: https://scgc.video.play/` for native playback, media preflight, and download requests. Metadata requests do not require a browser CORS proxy.
- Disable redirects in application-controlled API and media clients. Android's platform download service owns its transfer redirect handling; do not claim the app can impose the Node proxy's redirect policy on it.
- Deduplicate identical video URLs. Resolve fallback explicitly and name files using the actual downloaded quality.

The existing Web and Node proxy remain unchanged. These Android transport decisions do not relax the server's restrictions.

### Persistence and Refresh

The runtime Room database holds programme/date/content snapshots and the local download index. A separate user database owns favourites, viewing history and migration metadata; its first-open transaction imports legacy favourites once. Store successful empty archive responses as fetched results rather than treating an empty table as an unfetched request. A successful refresh replaces only the relevant cached snapshot in a transaction; a failed request preserves its last successful snapshot.

The repository exposes cache-backed flows with an explicit refresh state. Refresh the catalogue and the selected programme/date on destination entry while presenting their cache. ViewModels keep the displayed snapshot separate from the newest repository result; initial data appears immediately, but later successful differences require explicit acceptance, including a changed or empty response. Apply dates before contents, discard pending rows when their programme/date key changes, and retain errors without inventing content updates. Retry actions request data without automatically accepting pending changes. Do not fetch every programme's archive in the background. Cross-key isolation ensures a date change cannot render another date's contents while a new request is loading.

Use `SavedStateHandle` and saved navigation state for selected IDs, query, and selection-mode state. Restore only content IDs that still exist for the restored archive key. Native preferences have their own versioned schema and safe defaults; browser localStorage remains untouched, with no implied cross-platform synchronization.

### Download Consistency

Persist task and attempt identity, requested/actual quality, accepted context, source URL, network policy and a unique safe filename before transfer. Keep version-1 schema exports unchanged and migrate runtime rows with explicit legacy defaults. Reserve active content/quality keys transactionally. Retry replaces the attempt identity, so old batch targets cannot cancel new work.

Perform bounded HEAD/Range preflight and require the Referer on media requests. Resume only with a stable validator and valid 206 Content-Range; reject changed or non-resumable resources rather than append unsafe bytes. Media3 owns cache spans and transfer indexing. Restore nonterminal entries with stop reasons before any global resume; interrupted removals do not require a network context. Services lend execution permission and retain/cancel actual Calls through response-body closure. Transient failures wait for later constrained job leases using the same cache key; user pause and integrity failures require the corresponding explicit action.

Journal publication before MediaStore insertion. Recover a unique owned pending row by its planned filename, persist the URI, copy without upstream access, verify byte length and final readability, then clean private media. A copy or finalization failure retains the complete cache for retry. Deletion consent is tied to the exact attempt and URI. Removing a record cannot orphan private cache/index resources or delete an independently published file.

Legacy reconciliation retains DownloadManager IDs and resolves interrupted submission only by a unique owned URL/destination match; ambiguous matches block automatic retry. Check content URIs before local playback, sharing or external opening. File handoff uses temporary read grants. Download notifications return to the task list; notification permission is requested only when creating downloads.

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
