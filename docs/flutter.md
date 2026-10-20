# Flutter Client Architecture

The Flutter Android/iOS client lives under `flutter/` and connects directly to upstream services. It shares protocol rules and JSON fixtures with the other clients, while retaining separate application identity, databases and native resources. Setup, build and runtime-check commands belong to the [Flutter README](../flutter/README.md). The configured minimum versions are Android 10/API 29 and iOS 15; release acceptance must exercise the advertised OS/device matrix.

## Source ownership

| Location                                             | Responsibility                                                                                          |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| [lib/app](../flutter/lib/app)                        | Bootstrap, dependency composition, providers, routing and application lifetime                          |
| [lib/domain](../flutter/lib/domain)                  | Immutable models, programme/media/filename policies and repository/native contracts                     |
| [lib/data](../flutter/lib/data)                      | Bounded Dio metadata requests, Drift persistence, settings, history and durable download reconciliation |
| [lib/platform](../flutter/lib/platform)              | Native playback, background transfers, file publication/export/sharing and strict cover transport       |
| [lib/features](../flutter/lib/features)              | Programme library/archive, selection, playback, downloads and settings presentation/controllers         |
| [lib/design](../flutter/lib/design)                  | Shared theme, artwork and state presentation                                                            |
| [test](../flutter/test)                              | Domain, HTTP/SQLite fixture, controller, widget and platform-boundary tests                             |
| [android](../flutter/android), [ios](../flutter/ios) | Flutter native hosts, permissions, backup rules and platform integration                                |

Features consume domain contracts. Application composition owns repository/native lifetimes and supplies concrete adapters. Keep platform handles out of routes and persisted models; pin accepted programme metadata for active playback/download actions. Coding and boundary rules are in [Flutter Instructions](../flutter/AGENTS.md).

Application registration lives in `app/router.dart`; route adapters live in `app/routes/`, navigation actions in `app/navigation_actions.dart`, accepted/restored playback input in `app/playback_input_resolver.dart`, and concrete construction in `app/bootstrap.dart`. `AppServices` owns shutdown; independent cleanup continues after a failure. Native entry points register file and player capabilities owned by separate handlers.

Programme cards, exploration and archive regions are callback-driven presentation components. Favourite state separates confirmed storage from pending desired edits, with persistence errors and retry independent of programme refresh. Settings preserve optimistic in-memory preferences after a write failure and offer retry. Download selection/filter/batch state belongs to its controller; dialogs and actions belong to its action owner, not card rendering.

## Programme and persistence contracts

### Metadata and accepted snapshots

Metadata requests use a persisted installation UUID and the Android-compatible guest profile. Android supplies native device build values; iOS uses the explicitly documented compatibility profile. Covers, player requests and transfers use separate transports and receive no metadata identity headers. Media requests use the allowed HTTPS MP4 CDNs, the required Referer and `sctv-dl/<installed-version>` User-Agent.

Background refresh compares parsed model fields rather than serialized JSON: programme ID/name/cover, broadcast ID/date, and content ID/title/cover/video variants/publication time. Missing optional values, JSON key order and unused metadata do not create revisions. Additions, removals and effective display-order changes do; broadcast dates retain their existing deduplication and descending-date normalization. Unchanged snapshots keep their revision while advancing the fetched timestamp. A valid refresh repairs malformed cached items. Cancellation, stale-response rejection and serialized cache writes remain authoritative.

Follow [Upstream API](upstream-api.md) for ID validation, date normalization, quality mapping and URL policy. Metadata bodies are bounded to 2 MiB before buffering. Use keyed cancellation plus request generations; cancelling work and rejecting a late result are separate responsibilities. Refresh failures preserve the accepted snapshot. Successful empty results remain fetched results, and later changed or empty data waits for explicit acceptance. Apply accepted dates before their matching contents; batch selection prevents incompatible updates.

### History and backup

History shares exact programme/date/content identity between online and downloaded copies. Retain the newest 500 entries, record advancing progress at five-second intervals and flush pause, completed seek, background and exit. An ended item or 95% of a known positive duration is complete; incomplete playback resumes paused and completed playback starts from zero. Removed entries and cleared history invalidate stale session writes.

User preferences, favourites and viewing history belong to a user database, separate from the reconstructible runtime database. The user database and settings are eligible for backup; runtime metadata, installation identity, native task/resume records and media are excluded. On iOS, exclusion also covers the downloader's own task/resume/defaults storage. An actual OS backup/restore requires separate device verification. Cleanup of metadata/images preserves favourites, history, downloads and completed files.

## Appearance

The Flutter client uses neutral surfaces with blue accents and blue-tinted action surfaces, distinct from the Kotlin Android client's vermilion palette. The launcher icon matches the default light primary blue; the brand, functional icons, text actions, selected navigation and progress indicators share the primary palette. Tonal buttons and selected dates retain contrasting text over their pale blue surfaces. The default light and dark themes use coordinated blue roles; the optional system dynamic-colour preference still follows the device wallpaper.

iOS primary browsing pages use `liquid_glass_widgets` for the floating Programme Library/Downloads/Settings navigation. The toolbar and status area share one full-width backdrop blur, without separate glass capsules around the brand or actions. Shader initialization and application glass setup run only on iOS; Android retains its Material navigation and toolbars. The retained navigators, search state, download badge and business controllers remain shared. Glass follows the selected application theme and reduced-motion preference. The package approximates Reduce Transparency using Increase Contrast; it does not independently observe the iOS Reduce Transparency setting.

The bottom bar samples the retained page content through the package's scroll-driven brightness scope. Its foreground and light neutral tint adapt together; the bar stays outside the sampled region to prevent feedback. Moderate blur and tint soften mixed artwork while preserving background colour and edge refraction. The library, settings, history and archive lists scroll beneath the full-width blurred header, with content insets that keep the initial and final items reachable. The library title transition uses a transparent backing within this shared header. Blur activates only after vertical scrolling, preventing artwork below the toolbar from bleeding into the header at the top of the page. Downloads keep their filter and batch-management layout below the toolbar. Material scaffolds continue to own keyboard resizing and notices. Programme cards and player controls retain their existing presentation; glass quality and scrolling performance require device acceptance.

Archive and download batch actions use one inset glass surface on iOS, with scroll padding that keeps the final rows reachable above it. Choice sheets keep their original opaque Material presentation, modal routing, dismissal and result handling on both platforms. Quality choices can scroll on small or landscape iOS layouts. Covers hidden under floating headers or action bars cannot enter the shared-cover overlay.

Programme cards place the independent favourite action over 16:9 artwork and reserve the full lower row for the title. Grid height measures actual title layout with the current font, locale and text scaling, including CJK fallback metrics; it uses the full catalogue so filtering does not resize rows. Exploration uses a lightly tilted framed cover and a distinct primary action. The archive keeps its cover and title side by side on compact phones, switching to a text-first header at large text sizes.

## Browsing and navigation

Primary navigation contains Programme Library, Downloads and Settings. A heart icon beside the sort action filters only the catalogue list. Toggling it retains the exploration card, current search and ordering in the same scroll view; an empty result is shown beneath the toolbar without replacing the page. The toolbar history action opens a separate page above the navigation shell, retaining its search and scroll position across visits and passing the exact saved entry to playback.

Pending library/archive data appears as a compact, rounded blue notice anchored to the list entrance: below the library count/sort toolbar and at the archive content list after its date/count information. It follows that entrance during scrolling and is clipped to the page viewport, rather than using a fixed offset over programme headers. The refresh icon and “发现新内容” form one action with a 48-pixel minimum touch target. Its 160 ms fade/short slide respects reduced motion and never changes the scroll viewport. Accepting data does not force the library to the top; ordinary scroll clamping still applies if the updated list becomes shorter. The notice belongs to its route, is hidden on inactive retained tabs and during archive batch selection, and disappears after acceptance.

### Page and cover transitions

Primary destinations use a 20 logical-pixel directional slide and a 200 ms blend while retaining their navigators and scroll state. Favourite filtering transitions only the lazy catalogue region over 140 ms; the heart and search title/input use 120 ms feedback. Exploration swaps its title/artwork over 160 ms with reserved title space, keeping actions fixed. Interrupted transitions continue from the current blend and position, retain an opaque backing and exclude outgoing content from interaction, accessibility and Hero discovery. [sliver_tools](https://pub.dev/packages/sliver_tools) supplies sliver stacking while retaining viewport-only grid construction.

Opening an archive uses a 300 ms route transition and a shared cover from the selected catalogue or exploration source, including its rotation, frame and corners. Android entry, ordinary return and predictive back coordinate both pages on one route timeline: outgoing content fades during the first 35% and incoming content appears during the remaining 65%, using the Kotlin client's easing control points. Flutter's delegated transition animates the retained library together with its navigation bar; a stationary, opaque theme surface covers the fade-through gap and translated edges. Both pages keep their original layout and move at most 30 logical pixels horizontally. The right-edge gesture mirrors the direction. History, online playback and local playback reuse this page transition, including the previous page's complementary fade and opaque backing. Video textures remain live during the transition rather than using route snapshots; returning retains the archive layout and scroll position.

Timed cover/page movement uses FastOutSlowIn; Android dragging maps system progress directly to geometry without a second easing curve.

The shared cover remains in the navigation overlay throughout both fade phases. Cancellation reverses the current timeline, while completion continues from the release value without restarting. An early return during entry reverses that partial entry rather than switching opacity profiles.

iOS retains Cupertino edge-back handling. The archive header is available on the first frame and stays in place while dates load or fail; a cover clipped by archive scrolling does not participate in return flight. Returning preserves library scroll and search state; replacing the archive updates the current route's programme.

An asynchronous route push that interrupts a gesture restores the retained archive before it is revealed again. System gesture observation is route-owned so another delegated transition cannot unregister an active drag. Removing the archive during dragging or settlement releases the retained navigator's gesture lock. Image loading has no independent long fade.

Reduced motion suppresses visual transitions while retaining both platforms' back gestures, including diagonal Android gestures. Batch selection consumes back to exit selection before allowing route navigation.

Retained navigation branches release shared-cover placeholders when a shortcut replaces the detail/player stack with another tab. Returning to the library restores its artwork without rebuilding its list or resetting scroll position.

### Broadcast dates

Recent broadcast shortcuts display month/day and weekday. The full date chooser remains beside the section heading. Its fixed heading sits above a bounded, lazy list of rounded month groups, with weekdays and a blue selected row. Opening directly reveals the selected date without a later scroll correction; short lists shrink to their content. Choosing an older date keeps its shortcut visible, including after window or text-size changes, without moving the archive vertically.

## Playback and resource lifetime

Playback separates session/source/PiP coordination from controls visibility, history write ordering and OS window policy. A failed pause cannot skip history or native disposal. Window restoration remains owed after a partial failure, independently of the visible fullscreen layout; cleanup attempts both orientation and system UI restoration. Repeated disposal observes the same completion.

### Artwork and route transitions

Archive content cards share their artwork with the fixed playback surface. Accepted playback input builds that surface on the first route frame, avoiding a skeleton-to-player layout swap. The artwork remains above the live texture until route entry and player initialization (including any requested resume seek) complete, then fades out over 120 ms. Rendering and seek completion follow the upstream player; an exact first-frame guarantee is not part of this contract.

Android return-cover opacity complements the departing video's fade on the same route clock, independently of rectangle easing. The current video stays mounted underneath; cancellation retains its session, position and play state.

A clipped card cover does not participate in a flight or scroll itself into view; the page transition and fixed poster remain. Missing artwork uses the existing theme fallback. Reduced motion disables cover flights and the reveal fade.

### Controls and gestures

The player uses a dark control palette with readable foregrounds and highlighted selected options.

Player interaction follows the Kotlin client: tapping the video toggles controls during uninterrupted playback, with a 3.5-second idle timeout. Pause, buffering, errors, accessibility, keyboard focus, seeking and open menus keep controls visible; each hold has independent ownership.

Play/pause, elapsed time, the seek track, duration, speed, quality and fullscreen share one compact bottom row; PiP remains at the top right. Speed and quality labels have no dropdown chevrons. Their slots reserve candidate label widths from the first loading frame; replacing the quality placeholder with metadata does not move adjacent actions.

Time, speed and quality share the same label typography. Both time slots reserve the total duration's digit count, use tabular figures, and include spare horizontal room and explicit separation from the seek track. Durations of an hour or more use h:mm:ss; the track takes the remaining width without changing as elapsed digits advance. Large text or constrained viewports can scroll horizontally to preserve a usable seek target.

All player buttons share white press/hover/focus feedback and rounded corners, with transparent Material surfaces above the video so ink feedback remains visible. Speed choices are 0.75×, 1×, 1.25×, 1.5× and 2×; selecting one preserves the button's width. Menus open above their control and scroll within the video height. A single available quality also opens the menu to show the current selection; selecting it again does not reload playback.

Blank video accepts a single tap for controls, a double tap for play/pause, and horizontal seeking with a preview and one release-time commit. Cancelling never seeks. Full-width sensitivity is the smaller of duration and 120 seconds. Long press temporarily uses 2× while playing and restores the selected speed on cancellation, source changes, rotation, backgrounding, PiP and exit.

Fullscreen vertical gestures change brightness on the left and Android media volume on the right. Brightness restores on fullscreen exit/background/disposal; volume remains the user's system setting, including physical-key changes. iOS presents the public MPVolumeView for user-operated system volume; pointer and focus ownership keep it mounted until interaction ends.

A persisted hint appears once after fullscreen stabilizes. A non-consuming video ancestor cancels blank gestures when another pointer touches a control. Released interactions retire their axis and visibility hold synchronously, so late native completions cannot end the next gesture.

Controls and system edges retain their own touch arenas; inline vertical movement and touch exploration do not trigger surface gestures. Native environment effects belong to the platform adapter, separately from decoder/PiP lifetime.

### Fullscreen and PiP

Fullscreen requests both landscape orientations and hides system bars; back first exits fullscreen and restores the OS orientation policy. The same video surface/session and details scroll controller survive these layout changes. PiP displays only the video, suppresses fullscreen back interception, and retains the session until PiP exits.

Error recovery remains inside the video, including fullscreen. Explicit retry preserves the last usable position, speed, source and play/pause intent, unless backgrounding or committed navigation intervenes. Playing a completed video seeks to zero; opening a video still starts paused.

## Downloads, history and settings

### Downloads

Download result notices belong to their archive/player route, expire automatically, and are removed before navigating to downloads. Returning from the source route cannot leave a notice with a disposed callback on another tab.

Downloads keep a stable page header across loading, empty and failure states. Filters appear as all, active, completed, failed, cancelled and removed files; task groups follow the same order without all. Paused transfers remain active; failed transfers, interrupted transfers requiring retry and publication errors share the failed group, while cancelled tasks stay separate. Each group orders tasks by newest creation time first with a stable task-ID tie-breaker, so progress and native revision updates do not move cards.

Task cards pair a 16:9 content cover (falling back to the programme cover) with the title and programme/date/quality metadata, keep file actions in the upper-right menu, and pair status with icon-and-text actions without a filled background in the footer. Large text places artwork above the full-width title. Removed files retain their records in a neutral section with redownload/remove-record actions rather than appearing as failed transfers. Completed cards show file size beside their status and omit transfer-only network policy. Active transfers retain progress, byte totals and network policy; actions and footer content wrap at large text sizes without inventing sizes or transfer speeds.

State filters retain separate list positions. Batch management selects only the current filtered list, clears selection when filters change, and offers capability-aware pause, resume, retry, publication retry, cancellation, file deletion and record removal. Destructive batch actions confirm their scope; file deletion retains records and record removal retains existing files.

Each operation rechecks the current attempt and state, skips stale targets and reports partial failures without stopping the remaining tasks.

### Viewing history

History groups records by the local viewing day (today, yesterday or earlier), independently of the broadcast date shown in each card.

Compact cards pair a 16:9 cover with the title and programme/date metadata; large text keeps the artwork above the full title. In-progress entries show a thin progress track inside the cover when duration is known.

The footer distinguishes unstarted, resumable and completed entries, uses hour-aware timestamps, and offers plain icon-and-text playback actions. Removal lives in the overflow menu and does not trigger playback. Filtering has its own recoverable empty state, failed removal leaves playback available, and navigation/deletion preserve the list viewport and scroll offset where the remaining content allows it.

### Settings

Settings use aligned groups and scrollable selection sheets above the root navigation. Theme changes retain the existing navigation, selection and playback lifetimes.

## Native transfers and files

### Task ownership and recovery

Download task transitions use a short serialized lane; file inspection, publication, cleanup and export run outside it with exclusive ownership of the affected task. Native progress and unrelated observations remain available while those effects run. Explicit reconciliation joins already-owned effects before reporting file availability. Task attempts and durable revisions fence final commits, and shutdown drains accepted effects before releasing shared storage. Completed publication records retain their private recovery pointer until the public location is durable and cleanup succeeds.

The downloader owns native scheduling; there is no second Dart transfer engine or holding queue. Persist task/attempt identity, accepted context, actual quality, effective network policy, safe destination and native correlation identity before enqueue. Reserve active content/actual-quality identity transactionally. Each retry gets a new attempt, and old callbacks cannot mutate its replacement. Subscribe before reading native snapshots; reconcile events, tasks and real files on startup and foreground entry. Ambiguous enqueue recovery becomes interrupted instead of creating duplicate work. Cold notification taps wait for the router and acknowledge only their matching launch intent.

Batches accept at most 100 distinct items and report each result independently. Pause/resume actions follow native capabilities; unavailable resume data or an unsafe Range response must not append a new full response to old bytes. Unknown totals remain indeterminate.

Restored local playback never silently substitutes an online source.

### Storage and publication

Android transfers stage in app-owned storage and publish through application-owned MediaStore operations into public `Downloads/sctv-dl`. Same-name lookup alone cannot safely recover pending rows. Publication is separate from transfer completion: retain the private source until the public location is durable, and keep failed publication or cleanup retryable. Removing a terminal task keeps its completed file; deleting a file is a separate explicit action. Published public files can remain after uninstall.

iOS media lives under the application's `Documents/Downloads`, with Files visibility, local playback, sharing and explicit Save to Files export. References are relative to the current sandbox. Cancelling export keeps the local file. This application-owned folder is not the system-wide Downloads directory; unexported files disappear on app removal. Videos, runtime task state and installation identity are excluded from backup.

### Scheduling and network policy

Native holding queues schedule at most two transfers independently of the Dart UI. `仅 Wi-Fi 下载` sets the policy for new tasks; it does not rewrite existing transfers. On iOS this disables cellular transport and can permit other noncellular connections. Native background transfers retain the documented system-managed redirect exception; application metadata and artwork reject redirects, while native playback follows the upstream player redirect policy.

The hosted player dependencies, historical override differences and low-memory verification are documented in the [Flutter README](../flutter/README.md#player-dependency-and-licenses). `video_player` owns decoding and public seeks; the application owns controls, source replacement, play intent and cleanup. `pip_kit` provides explicit Android/iOS PiP through its exported platform API, with authoritative Android Activity state delivered over an application-owned channel. Audio focus/interruption policy belongs to `audio_session`; display wake ownership belongs to `wakelock_plus`.

Source replacement waits for native disposal before allocating the next decoder, restores position/speed/intent, and attempts rollback on failure. Disposal cancels pending readiness and shares the original release completion. An unconfirmed native release blocks later allocations rather than treating a timeout as successful cleanup. Redirects, first-frame output and forward buffering follow the official native implementation; the adapter cannot enforce a forward-buffer duration or byte budget. Interruptions and noisy audio-route changes pause without automatic resume. PiP retains the same session; dismissing Android PiP pauses playback even when Flutter was already backgrounded.
