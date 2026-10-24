# Native Apple Architecture

The SwiftUI client in `apple/` supports iOS/iPadOS 26 and macOS 26. One `SCTV` multiplatform application target and shared scheme build for iPhone, iPad and native Mac. `Apps/Shared/Application/SCTVApp.swift` owns the shared application entry point, with platform-specific delegates and scenes; macOS retains AppKit and native SwiftUI windows. The shared `SCTVUITests` target follows the selected destination.

SDK-specific build settings select each platform's Info.plist, entitlements and bundle identifier. Release preserves the existing identities (`dev.sctvdl.apple.ios` or `dev.sctvdl.apple.mac`); Debug adds `.debug` and uses the product name `SCTV Debug`, allowing side-by-side installation with separate sandboxes. It connects directly to upstream programme/media services, with independent local state and no Node service requirement. Build commands and verification scope belong to the [Apple README](../apple/README.md).

## Ownership

| Owner                                    | Responsibility                                                                                                          |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `Apps/Shared` and platform configuration | Dependency composition, navigation, application delegates, settings windows, player presentation and native file panels |
| `SCTVCore`                               | Immutable programme/history/download values, URL and quality policies, typed states and service protocols               |
| `SCTVData`                               | Bounded metadata transport, decoding, SQLite migrations, snapshots, preferences, favourites and history                 |
| `SCTVMedia`                              | Bounded HTTP ranges, resource loading, the single AVPlayer session, playback-history recording and player presentation  |
| `SCTVDownloads`                          | Durable queue transitions, background sessions, staging, publication, bookmarks and file leases                         |
| `SCTVFeatures`                           | Observable page models and native SwiftUI catalogue, archive, library, downloads and settings views                     |

Within `Apps/Shared`, `Application` owns startup, dependency composition, lifecycle delegates and workspace navigation; `Playback` owns the player destination and playback-to-download coordination; `Downloads` owns download composition and native file sharing; `Settings` adapts application services to the settings view; and `Diagnostics` contains fixture adapters and the media probe. `Assets.xcassets` and generated `Fixtures` remain resource directories at the shared root. Xcode's synchronized folder includes these subdirectories in the same application target.

Keep the dependency graph explicit: data, media and download targets depend on core contracts, not features. Features depend on core service contracts. Application roots construct concrete services; the download engine does not import GRDB. GRDB owns database transactions and Nuke owns artwork loading. Swift 6 concurrency checking applies throughout. Extract services around real workflows, concurrency boundaries or resource lifetimes; do not add a global store or generic use-case framework. See [Apple contribution instructions](../apple/AGENTS.md) for readability and cleanup conventions.

`ProgrammeActions` prepares online/history/local playback requests and starts downloads through application services; `WorkspaceView` owns navigation and presentation tokens. `ArchiveDestination` owns scene-restored archive state. Download pages own selection and captured confirmations, while `DownloadCard` receives task and presentation inputs. Select-all lives in the batch footer, keeping the native selection toggle in the same toolbar position during rapid taps. Artwork presentation, loading/cache configuration and URL validation have separate owners in `Design`.

## Navigation and browsing

The main destinations are 栏目, 资料库 and 下载.

Catalogue sorting keeps the current viewport rather than following a programme ID to its new grid position; the navigation stack retains the catalogue scroll offset when returning from a programme. `CatalogueView` captures the content offset before opening a programme and restores it after navigation updates the scroll insets. User scrolling, search and filter/sort changes cancel pending restoration.

iPhone/iPad use native tab bars and navigation stacks without an iPad sidebar toggle; Mac uses a sidebar with full-row hit targets and independent native detail navigation. Navigation transitions and trackpad gestures follow system behavior; the app does not add its own transition or gesture recognizer. The Mac player is a separate window backed by the same application-wide player session. Scene storage retains route IDs and archive selection; shared preferences do not own individual windows' navigation.

Catalogue and broadcast results distinguish an accepted snapshot from a pending refresh. Cached results remain visible while refreshing; explicit acceptance prevents background refresh from changing a selected date or active batch. Requests have query ownership and cancellation, while page generations independently reject stale results. Date acceptance resolves the retained selection before loading its contents. Full episodes and clips use the shared programme rules and Shanghai publication ordering.

Library content combines unfinished history, favourite programmes and history grouped by local calendar day. History keeps the newest 500 entries. Day headings use explicit Chinese date formatting while retaining local-day grouping. History uses the shared media-card column policy within each day, with day headings spanning the content width. The clear-history confirmation is anchored to its toolbar button.

Progress writes are throttled to five seconds, with immediate settled seek, pause, end and lifecycle writes. Ended playback or at least 95% of a known duration marks completion; completed entries resume from zero. Session tokens and increasing write sequences prevent an older player from overwriting a newer session or recreating deleted history.

## Visual design and adaptive presentation

The Apple client uses a warm neutral canvas, vermilion accents and charcoal dark surfaces. Shared presentation colours and card treatment belong to `SCTVFeatures/Design`; feature views own their layouts. Artwork and editorial typography establish hierarchy, while native navigation, menus and AVKit remain responsible for platform interactions. Native controls are not a restriction on custom content design.

### Catalogue, archives and card layout

The catalogue combines a programme exploration feature with a responsive artwork grid and independent favourite controls. Search and favourite filtering apply to the grid while preserving exploration. Archives pair cover art with the programme identity and favourite action, expose recent dates directly with an on-demand searchable date browser, and distinguish large full-episode cards from compact clips. The date browser initially presents only the selected month, with previous/next available-month buttons and a month menu. Its bottom search accepts digits with or without date separators across the full archive. Month groups and normalized search keys are prepared once per presentation, and reopening restores the selected month and date. iPhone/iPad retain the native sheet and search field; Mac uses a compact popover anchored to the date button with lazy date rows.

Continuing, history, downloads and standalone archive sections share one width policy across iPhone, iPad and Mac: an available page width of at least 800 points uses exactly two columns; narrower windows and accessibility text sizes use one. Media-card grids never expand to three columns. Section/date headings and empty/loading states span the content width. Catalogue and favourite artwork grids retain their separate adaptive tile layout. Wide archives show full episodes and clips alongside one another when both are present, or a two-column card grid when only one kind is present.

Library continuation and history cards limit titles to three lines without reserving unused lines, with fixed-size compact covers and balanced insets, with whole-card playback and trailing native swipe-to-delete in narrow iOS lists (context-menu removal in wide iPad grids and on Mac); downloads preserve explicit selection while displaying artwork, task metadata, progress and capability-aware actions.

### Artwork and exploration

Artwork always occupies a 16:9 container, independent of the image's intrinsic size or loading state. Nuke decodes thumbnails for the rendered width and display scale, rounded to reusable pixel buckets and capped at 2048 pixels. The dedicated decoded-image LRU cache is limited to 64 MiB and 128 entries, separately from the encoded HTTP response cache; scrolling through covers must not inherit Nuke's device-memory-based default budget.

The exploration card selects a random programme when the catalogue first loads in a session. Navigation, tab changes, filtering, sorting and accepted snapshot updates preserve a still-valid choice. The shuffle action excludes the current programme when alternatives exist. Its cover opens the programme archive, and the shuffle label owns an 88-by-44-point minimum hit target.

The exploration card uses intact, slightly rotated artwork over a paper backing and a softly blurred copy of the cached cover for ambient background color. Narrow cards place artwork above a compact row with a 24-point programme title and entry arrow; wide cards use a 28-point title and a prominent right-hand artwork column. Both title sizes scale with Dynamic Type. Standard titles occupy one line without an empty second-line reservation; accessibility text sizes use a vertical layout with wrapping titles.

### Navigation controls

Catalogue cards use compact single-line titles. Mobile catalogue refresh uses the pull gesture; Mac retains a toolbar action. Catalogue, library and downloads use native navigation titles and toolbar actions. Catalogue and library share the same settings destination on iOS/iPadOS; Mac exposes settings through the sidebar and standard app menu without duplicate page-toolbar buttons.

Navigation-bar actions use icon-only labels with Chinese accessibility names and help text, except select-all/deselect-all, which keeps text to distinguish it from Done. In-content playback and batch actions retain text labels. On iPhone/iPad, large titles collapse with scrolling while settings and editing actions remain in the navigation bar. Catalogue search uses the system search field below its title, together with native pull-to-refresh. Mobile detail destinations explicitly restore their navigation bar.

### Archive rendering and date browsing

Download loading and empty rows share the page canvas. Archives remain loading through the dates-to-contents handoff and show an empty state only after receiving an accepted empty snapshot. Archive episode grouping and clip ordering are materialized when accepted snapshots or sort order change, keeping timestamp parsing and sorting out of scroll-driven rendering.

Full-episode titles use two lines at standard text sizes and three at accessibility sizes. Compact clips reserve three title lines beside larger covers, keeping long and short titles at the same card height; the complete title remains available to assistive reading and playback. Clip ordering is exposed beside the section heading, programme selection is a direct navigation-bar action, and mobile archive refresh uses the pull gesture. Overflow controls retain a 44-point hit area inside their labels.

Date rows are constructed only when the date browser is presented, using a native List on iPhone/iPad and a lazy stack on Mac; an inline Picker would build thousands of options during archive updates. The browser groups compact rows by month in reverse chronological order and reopens at the selected row without moving that date into a separate section. Native search retains its platform placement, including the bottom field on iPhone; only the selected date receives accent styling. Date search ignores hyphens, accepts numeric year/month/day input such as `202610` or `20261023`, and uses the numeric keyboard on iPhone/iPad. Unknown upstream date labels remain available in a fallback section.

Narrow archives use one lazy stack for episode and clip rows; wide archives retain their two independently targeted columns. Returning from playback reconnects archive subscriptions without clearing the accepted rows for the same date, preserving the visible list and its scroll offset. The live scroll anchor stays in the page model; scene storage saves it when leaving the archive or leaving the active scene, so scrolling does not repeatedly invalidate the destination through persistence updates.

### Mobile player presentation

iPhone and iPad playback is a pushed navigation destination in the originating tab, with the page navigation and tab bars hidden. The video owns its back button and preserves native leading-edge interactive navigation outside fullscreen; returning stops playback and restores the originating browsing route. Replacing playback removes obsolete player destinations from retained tab stacks.

One AVPlayerLayer host survives inline/fullscreen layout changes. The overlay has one central play/pause action, AirPlay at the upper right and fullscreen at the lower right. Inline speed/quality choices occupy the upper controls; in fullscreen they follow the progress slider before fullscreen. Options use trailing selection marks and keep controls visible while presented. Wide iPad and Mac layouts place programme details beside video; smaller windows stack them.

### Mac player presentation

Mac retains its independent native player window with one AVPlayerLayer surface and a floating two-row control bar. The bar uses an in-window AppKit HUD material, a large central play/pause button, volume on the left, and arrow-free speed/quality choices, AirPlay, PiP and fullscreen on the right. The lower row holds the timeline with an AppKit slider and capsule thumb; AppKit retains pointer tracking and accessibility behavior. Ten-second skips flank play/pause. Narrow windows wrap controls without dropping actions. Pointer movement reveals the bar; pause, VoiceOver, slider interaction and open options keep it visible. Seek previews retain the requested position until AVPlayer settles; rapid requests wait for the previous seek and only apply the latest target.

A single window-scoped keyboard owner handles shortcuts independently of alternative control-bar layouts and reads live playback state. Space toggles playback, Left/Right seek ten seconds from the current or pending position, Up/Down adjust video volume by five percent, and F toggles fullscreen. Text input, open options and other windows retain their keyboard handling.

Transport actions and keyboard volume changes briefly show centered visual feedback in a fixed 96-point square; seek feedback shows the direction and ten-second step without repeating the timeline position. Repeated actions renew the feedback lifetime.

Double-clicking the video toggles native fullscreen without making control double-clicks fullscreen actions. Programme details remain visible in windowed mode, preserving the side-by-side layout in wide windows. There is no details visibility toggle or player window toolbar; native fullscreen shows only video and restores details on exit. The surface owns PiP, fullscreen notifications and their cleanup; closing the player window also ends detached PiP. Details do not duplicate these controls.

Titles initially occupy at most three lines; tapping expands them in place, and tapping again collapses them without interrupting playback. Player presentation metadata never retains a local-file lease, and local playback does not offer an online download or quality switch.

### Gestures and presentation lifetime

Horizontal video gestures preview a bounded seek and commit it on release. Both video gestures and the progress slider retain the released target until AVPlayer completes the seek, then read the settled position rather than a queued older snapshot. The leading screen edge remains reserved for navigation. While iPad playback hides tab chrome, its controller temporarily uses tab-bar mode so the adaptive sidebar cannot intercept the back gesture; leaving restores the previous tab mode and sidebar visibility. Mobile history rows use native lazy lists for trailing swipe deletion. Empty library sections and the history entry share icon, inset and typography treatment.

Vertical gestures adjust brightness on the left and the player's volume relative to system volume on the right. Brightness is restored on backgrounding and disposal; hardware volume buttons retain system-volume ownership. Long press temporarily uses 2x without changing the saved speed, and release, cancellation, interruption or source replacement revokes the temporary rate. Seek completion reapplies the latest playback intent.

System PiP may start automatically when a playing iPhone/iPad video enters the background. The surface owns its PiP delegate, notifications and a cancellable fallback pause; failed PiP pauses background playback. Returning to the archive disposes the surface, stops PiP and releases the session. Real-device automatic PiP and external AirPlay routes require separate acceptance from simulator tests.

`PlaybackCoordinator` owns a shared `PlayerSeekInteraction` for mobile sliders, iOS gestures and Mac controls. It serializes seeks and tracks preview ownership; cancellation from a departing adapter cannot cancel another adapter's newer request. Source replacement revokes pending interaction work. Overlay visibility derives from gesture activity, the pending seek and presented options instead of a writable aggregate flag.

### Accessibility

Large text switches compact artwork rows to vertical layouts. Content remains scrollable, uses semantic font sizes and keeps visible actions separate from overflow menus. Automatic package tests do not establish visual, VoiceOver or fullscreen acceptance; inspect screenshots and navigation on each supported form factor.

## Persistence and requests

User SQLite storage holds preferences, favourites and history. Runtime SQLite storage holds programme snapshots and durable download records; clearing programme cache does not clear downloads or user data. Runtime caches and managed downloaded media are excluded from backup through native resource attributes. Attribute tests are not backup/restore acceptance.

Preference edits carry accepted revisions. Failed saves remain visible and retryable; a failed initial read cannot silently overwrite existing data with defaults. Metadata decoding validates upstream values beyond `Codable`, preserving string IDs, safe numeric-ID limits and shared quality/date/filename fixture semantics. Metadata requests have independent header/body deadlines, a 2 MiB body limit and redirect rejection. Installation identifiers belong to metadata headers, never media requests. IDs remain strings across decoding and storage.

## Playback and files

`SCTVCore/Playback/PlaybackRequestResolver` prepares playback requests through the programme and history protocols. `SCTVCore/Network/UpstreamRequestProfile` owns the shared upstream User-Agent used by metadata and media requests. Preparation preserves quality fallback and treats history as optional; resolving a saved entry refreshes programme metadata while retaining that entry's resume position, with completed entries restarting at zero. Missing programmes and upstream failures remain distinct errors.

Opening a programme starts paused. One application-wide AVPlayer owns the active session, source replacement, interruption state and cleanup. Tap-time request tokens reject older metadata resolutions. Presentation tokens protect a newer player from an older window or navigation destination's delayed dismissal. Local playback retains a file lease for the session and never silently falls back to an online URL.

iOS audio configuration and deactivation are serialized across player lifetimes. AVPlayer activates audio only when playback starts. Teardown uses asynchronous deactivation when supported by the SDK and OS, with a dedicated background queue for the iOS 26 fallback and category configuration. A replacement waits for the previous deactivation; player cleanup commits before awaiting completion so a late close cannot clear a newer session. Deactivation failure is best effort and does not prevent the next configuration.

Online playback validates the shared HTTPS media allowlist, rejects redirects and requests at most 256 KiB per range, with at most four active resource reads. The resource loader cancels reads with its owner. Range responses must match the requested offset and declared length; truncated or ignored nonzero ranges fail rather than appending whole-resource bytes. Resource cancellation and bounded buffering belong to the transport owner. Unsupported AVURLAsset header options are not used. This bounded strategy still requires physical-device and production-network performance acceptance.

## Download lifecycle

Preparation resolves actual quality and safe names before reserving records. Batches contain at most 100 distinct items. SQLite enforces active content/quality uniqueness. Each task pins programme metadata, source, destination and cellular policy; later preference edits affect new tasks only. Retries receive new attempt IDs. Commands and native callbacks must match the current attempt, revision and native correlation.

`DownloadCoordinator` remains the single actor owning queue state. Its reconciliation steps separate native-event subscription, task recovery and artifact cleanup; enqueue and resume share native-transfer attachment and early-callback recovery. File publication and observer snapshot broadcasts are distinct operations. The download page models recovery as loading, failed or ready, and failed recovery keeps commands blocked until an explicit retry succeeds.

Fixed background URLSession identifiers represent cellular policies. The delegate synchronously adopts temporary files into owned staging before returning. Durable staged files, failure receipts and resume references recover callback/database interruption windows. Background-event completion is acknowledged only after ordered callbacks and persistence have drained. Mac quit gives persistence and reconciliation a bounded three-second drain; durable attempts recover on the next launch if it expires. Native background sessions manage their own redirect behavior; this differs from the custom playback transport's redirect rejection.

Transfer completion enters publication, not completed. Publication validates playable media, copies to an attempt-owned partial file and atomically moves to a collision-safe final name. Staging remains until the guarded completed record is durable. Recoverable destination, resource-access or space errors retain staged bytes for publication retry. Confirmed invalid media permits a fresh transfer; an operational validation error never discards staged bytes. Attempt identity and file identity prevent replacing or deleting unrelated files.

### Download and batch presentation

Download lists use persisted creation time, newest first, with task ID as a deterministic tie-breaker. Progress, state changes and retries do not reorder existing tasks, including after relaunch. Archive batch downloads share the download page’s bottom action bar, safe-area coverage and interruptible selection transition. Selection exposes Select All and Done in the navigation bar, hides individual content menus, and uses a text-only capsule action for the selected programmes. Compact iOS layouts hide bottom navigation while selecting; regular-width iPad top tabs remain available.

Horizontal archive, continuing, history and download cards share 12-point content insets and 14-point cover-to-text spacing. Compact covers share 12-point corners and a lower-right material-backed accent playback badge; history retains its progress bar. Download cards limit titles to two lines. Completed cards play when tapped anywhere outside their independent secondary-action menu, with no separate playback button. Other states retain text-only transfer actions. Row taps select tasks only in explicit selection mode.

The explicit Select/Done mode enables card selection in wide grids and on iPhone/iPad, retaining native list selection in narrow Mac windows, keeps the navigation title mode unchanged, replaces the task summary with the selected count, and groups select-all with capability-aware batch actions as equal-width buttons in a bottom inset. The iOS bottom tab bar is hidden during selection so navigation and batch actions do not compete for the same area.

Selection changes accept every tap. On iOS, one interpolated progress value drives cover selection badges and the bottom action area. Download selection uses the archive style: a circle over the cover’s lower-right corner and an accent outline on selected cards, without a leading selection lane or changes to card width.

A page-owned controller uses `UITabBarController.setTabBarHidden(_:animated:)` for navigation visibility, rather than changing the system bar's alpha, transform, or rendering layer. It coalesces visibility requests into a main-actor task outside the SwiftUI representable update, because changing native tab visibility can synchronously lay out alerts and write their presentation bindings. It reads the latest target, sends only target changes so layout callbacks cannot restart an in-flight transition, cancels queued work when leaving the page, and restores the prior visibility.

The action area is anchored to the screen bottom with the window home-indicator inset; a separate clear inset reserves list space. Its controls and backdrop move and fade together, independently of the system tab bar changing the content safe area. On exit, the outgoing action labels remain until the footer disappears even though selected IDs are cleared immediately. Regular-width iPad layouts keep their top tabs visible because these do not overlap bottom actions. Reduce Motion disables these movements.

Single-task controls are hidden while selecting; leaving selection or changing filters clears the selected IDs. Single-task destructive confirmations remain anchored to the card menu. Batch deletion uses a centered alert with the actionable command count and explains whether files or download records remain. Both paths preserve the captured attempt guards.

### Storage, settings and file actions

Managed iOS files live in `Documents/Downloads` and are visible in Files. Mac uses application-owned storage by default and supports explicit external directory selection. Its settings place directory actions beside the current download location; restoring the application directory is available only while an external destination is selected.

Cache maintenance uses a second row with its preservation note on the left and the accent-colored cleanup action on the right. Both Mac and iOS require confirmation before clearing programme data and artwork caches; cancellation leaves caches untouched. Cleanup results use a dismissible native alert rather than adding a row to the settings form.

Security-scoped bookmarks remain in native user storage; renewing access replaces the existing bookmark identity so affected tasks can recover. Playback, reveal and export retain balanced access leases throughout the operation. Missing completed files become actionable missing-file records. Removing a record preserves its file; deleting a file preserves a missing-file record. Export cancellation preserves the original media.

## Verification ownership

The [Apple README](../apple/README.md#verification-scope) owns commands and the distinction between package tests, fixture UI tests and operating-system behaviour. [Repository Maintenance](maintenance.md) owns CI and dependency policy. Per-run results belong in ignored build output or CI artifacts.
