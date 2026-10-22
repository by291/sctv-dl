# Native Apple Client Design

Date: 2026-10-22

Status: The written specification was approved on 2026-10-22. See the [implementation plan](../plans/2026-10-22-apple-client.md) for execution tasks. This document does not describe an implemented or runtime-verified client.

## Intent and scope

Build an independent SwiftUI client for iPhone, iPad and Mac, with iOS 26, iPadOS 26 and macOS 26 as the minimum supported systems. Preserve the useful programme, playback and download capabilities of this repository while adopting Apple navigation, controls, accessibility and window conventions.

Success means a coherent native experience on each platform, explicit module and resource ownership, durable downloads and history, and testable business rules. Reuse protocol semantics and JSON fixtures, not Android/Web layouts or Flutter implementation details. Existing clients remain independent.

The first release includes catalogue search and ordering, favourites, broadcasts by date, full episodes and clips, online and local playback, viewing history, background downloads, file management and settings. Each installation has its own state. Cloud synchronization, automatic import from other clients, widgets, accounts and editorial recommendations are outside this release. AirPlay is an optional follow-up capability, contingent on media transport verification.

## Architecture decision

Use two application targets, iOS and macOS, backed by a local Swift package with explicit target dependencies. The iOS target serves both iPhone and iPad. The macOS target is a native Mac application, not a Catalyst build.

A single application target with widespread platform conditionals would couple navigation and lifecycle decisions. Separate complete implementations would duplicate protocol rules and recovery logic. Shared packages with platform-owned shells provide the intended balance.

Applications connect directly to upstream services using the contracts in [Upstream API](../../upstream-api.md). A Node deployment is not a normal runtime dependency. If supported native media loading cannot satisfy the verification gate below, revisit the media transport decision explicitly before expanding implementation.

## Navigation and presentation

Top-level destinations are 栏目, 资料库 and 下载. The library destination contains 继续观看, 收藏栏目 and 观看历史. Search on the catalogue filters programme names; it does not imply an upstream full-text episode search.

| Concern            | iPhone                                                   | iPad                                                                                 | Mac                                                |
| ------------------ | -------------------------------------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------- |
| Root navigation    | System `TabView` with a navigation stack per destination | Sidebar-adaptable navigation with selection-driven split content at sufficient width | Collapsible sidebar and resizable split content    |
| Programme browsing | Adaptive artwork grid, then pushed archive               | Programme list and archive detail at wide sizes                                      | Programme list and archive detail                  |
| Broadcast date     | Scrollable, month-grouped sheet                          | Popover, adapting to a sheet when compact                                            | Toolbar popover                                    |
| Playback           | Native player presentation with fullscreen support       | Player presentation with fullscreen and picture-in-picture                           | Dedicated resizable player window                  |
| Downloads          | List, explicit selection mode and batch toolbar          | Multiselect list and contextual toolbar                                              | Multiselect list, context menus and Finder actions |
| Settings           | Toolbar entry to a grouped form                          | Toolbar entry to a size-appropriate form                                             | Standard `Settings` scene and Command-comma        |

Use actual available window width rather than device identity to select compact navigation. Resizing a window or collapsing columns preserves selected programme, date and route identity. Each destination retains its search, selection and scroll context during ordinary navigation. Persist stable identifiers for restoration, never native handles or View instances.

On Mac, browser windows own independent navigation and selection. Downloads, repositories and user preferences are shared within the application. The first release permits one active playback session per application: opening another item replaces the current session through an explicit capture-and-release transition; opening the same item focuses its existing presentation. This keeps audio ownership and history ordering deterministic.

### Page composition

- Catalogue: native title and search, ordering and favourite filter, followed by a regular 16:9 artwork grid. Use content-driven column counts and dynamic text sizing. Do not copy the tilted exploration card.
- Archive: compact programme identity and favourite action, date selection, full-episode section and clip list. Clips retain stable IDs and an explicit publication-time order. Batch selection is a distinct mode with contextual actions.
- Library: continue-watching entries, favourite programmes and a route to complete history. History groups by local viewing day, while programme broadcast dates retain their domain meaning.
- Downloads: active, completed and needs-attention filters with clear paused, cancelled, failed and missing-file states. Unknown totals show indeterminate progress. Individual and batch commands use the same applicability rules.
- Settings: default playback quality, system/light/dark appearance, download network policy, storage management and application information. Mac adds destination selection; iOS/iPadOS expose local files and export.

Use system typography, SF Symbols, semantic colours and a restrained blue accent. Native bars, sidebars and controls provide Liquid Glass; artwork and reading surfaces should not accumulate custom glass backgrounds. Settings use native forms. Destructive operations state whether they delete a file, remove a task record or clear history.

### Interaction and accessibility

Every actionable icon has a meaningful accessible label. Support VoiceOver, Dynamic Type, increased contrast, reduced transparency and reduced motion. Large text may move artwork above text or remove decorative artwork. Focus and keyboard selection follow native controls; context menus supplement visible primary actions.

Mac supports standard search, settings and window commands. Space controls playback only when the player owns keyboard focus and text entry is not active. Escape dismisses eligible temporary presentations. iPad supports hardware-keyboard navigation and pointer input.

Loading, valid empty results, filtered-empty results, unavailable offline data and refresh failures are distinct states. Cached content remains usable during refresh. Refresh errors appear within their owning region. Changed snapshots offer 有新内容 without moving the user's viewport; accepting dates precedes loading their matching contents. Incompatible snapshot acceptance is disabled during archive batch selection.

## Source and dependency ownership

Proposed layout; these directories are not created by this specification:

```text
apple/
  Apps/
    iOS/                         # Composition, lifecycle, adaptive shell
    macOS/                       # Composition, windows, menus, application exit
  Packages/
    SCTVKit/
      Sources/
        SCTVCore/                # Value models, policies and consumer-facing ports
        SCTVData/                # API parsing, SQLite repositories and caches
        SCTVMedia/               # Playback sessions, transport and history sampling
        SCTVDownloads/           # Durable tasks, system transfers and file publication
        SCTVFeatures/            # Feature views, presentation models and shared styling
      Tests/                     # Tests grouped by owning target
  UITests/                       # Platform navigation and accessibility flows
```

`SCTVCore` has no SwiftUI, AVKit or database dependency. Data, media and download targets depend on core contracts and do not depend on features. Features depend on core contracts; applications supply concrete implementations. Apple player representables live with the media integration and are injected into feature composition, so feature views do not construct playback engines. A platform-specific implementation belongs in a dedicated file rather than repeated conditional blocks throughout shared views.

Use SwiftUI, Observation and Swift Concurrency. Page models are `@MainActor`; immutable boundary values are `Sendable`. URLSession owns HTTP transport. GRDB owns SQLite access, migrations and observation. Nuke/NukeUI own artwork loading, downsampling and bounded caches, with a dedicated transport that applies image policy. AVFoundation/AVKit own playback and native controls. Background URLSession owns native file transfers. Use Swift Package Manager and lock stable compatible releases during implementation.

Do not add a global Redux-style store or generic use-case framework. Extract a service when it owns a real business workflow, concurrency boundary or resource lifetime. Dependency composition remains explicit at the application root.

### File and function conventions

An archive feature consists of an `ArchiveView` for composition, an `ArchiveModel` for presentation state/actions, and focused date, episode and clip components. Repository operations own loading and caching. Views do not perform SQL, construct requests, or manage download sessions.

Group dependencies, stored state, derived state, actions and lifecycle methods visibly. Within functions, separate validation, computation, external calls and state commits with logical blank lines. Use named steps for distinct rules, not one-line wrappers that obscure a straightforward operation.

Use enums with associated values for mutually exclusive states. Keep error recovery context with the failed state. Comments explain cancellation versus stale-result rejection, commit guards, persistence ordering and resource release. Documentation, comments and test descriptions are English; product copy is Chinese. Establish these conventions in `apple/AGENTS.md` when implementation starts, and enforce mechanical formatting with a Swift formatter.

## Data and persistence

Boundary decoding performs explicit validation after decoding; `Codable` alone is not business validation. Preserve string IDs, upstream safe-integer restrictions, date normalization, optional fields, quality mapping, fallback, source deduplication, full-episode classification and filename rules. Reuse the fixtures under `shared/fixtures/` as test resources without modifying production contracts to accommodate Swift tests.

Metadata requests use a persisted installation UUID and the documented Android-compatible guest profile. Apple uses the existing compatibility values, not a claimed official iOS profile. Metadata identity headers never reach artwork, media probes, playback or downloads. Bound metadata bodies to 2 MiB during reception, before full buffering. Separate response-header deadlines from bounded body reception and long-lived media transfers.

Application-controlled requests validate initial URLs and reject redirects. The proposed custom playback transport applies the media allowlist to each request and rejects redirects. System background downloads retain the existing documented system-managed redirect exception; initial URL validation still applies. Do not claim that background delegate hooks enforce a redirect policy the OS does not expose.

Use separate user and runtime databases. User storage contains favourites, preferences and the newest 500 history entries. Runtime storage contains programme caches, task attempts, reconciliation records and resume references. User data is eligible for backup; reconstructible cache, installation identity, download state and media are excluded. Store sandbox-relative media paths rather than absolute container paths. Mac external destinations use security-scoped bookmarks with balanced access lifetimes and explicit stale/denied recovery.

Cache snapshots distinguish never fetched from successfully empty, compare normalized meaningful fields, and preserve accepted data after refresh failures. Keyed cancellation stops unnecessary work; request generations reject results that arrive after cancellation. An actor can reenter across `await`, so generation and attempt checks remain necessary before state commits.

Preference changes remain usable in memory after a failed save and expose retry. Serialize writes and distinguish local edit revisions from incoming snapshots. Cache cleanup must not remove favourites, history, task records or completed files.

## Playback lifecycle and media gate

The playback service owns one session, its pinned content metadata, AVPlayer, source loading, observations and history token. A feature routes an intent to this service and renders the resulting state. UIKit/AppKit player wrappers own presentation integration, not a second engine.

Opening content starts paused. Incomplete history restores its saved position only after a settled seek; completed history starts at zero. Quality switching preserves position, speed and explicit play intent, and discloses actual-quality fallback. Source replacement suppresses transient zero-position samples. Retry uses pinned content identity and the last valid snapshot. Backgrounding or closing revokes pending automatic-resume intent.

Closing captures and pauses immediately. Retain the presentation/session until native dismissal is committed, then release observations, pending media requests and player resources. Interactive dismissal cancellation must not strand an invalid session. PiP transfers presentation ownership while retaining the same session. Normal off-screen playback pauses unless that session is legitimately retained by PiP. Audio interruptions or route loss pause without automatic restart.

History uses programme/date/content identity for both online and local copies. Save advancing progress at five-second intervals and flush settled seek, pause, end, background and close. Completion is an ended event or at least 95% of a known positive duration. Session ownership and sequence guards prevent old players from overwriting newer progress. Removing history invalidates outstanding tokens. Persistence failures leave playback usable and never claim durable success.

### Required feasibility gate

The upstream media contract requires Referer and a product User-Agent. Apple explicitly states that `AVURLAssetHTTPHeaderFieldsKey` is unsupported, so it must not be the production dependency.

The preferred candidate is an AVAssetResourceLoader-backed source using a custom asset scheme and controlled URLSession MP4 range requests. This is a design hypothesis, not a validated transport. The adapter must satisfy requested byte ranges incrementally, report content length and type accurately, handle cancellation and concurrent requests, bound retained buffers, and reject unsafe partial-response semantics. It must never buffer an entire episode in memory or append a full `200` response to an existing partial file.

Before broad feature implementation, verify both allowed media hosts, initial paused readiness, first-frame output, forward/backward and near-end seeks, quality replacement, error retry, PiP, dismissal and bounded memory on the three target platforms. Use synthetic fixture media for complete playback tests and HEAD or small Range requests for live upstream checks. Real-device background/PiP behaviour is a separate gate from simulator success.

If this candidate fails required playback or lifecycle behaviour, stop expansion and revise this transport decision. A supported backend media proxy is an alternative only after explicitly revisiting the independent-client runtime requirement. Do not silently introduce an unsupported header option, full-file buffering or an external service dependency. AirPlay is evaluated separately and is not an initial acceptance requirement.

## Download lifecycle and files

One application-owned download service coordinates a durable queue with system background URLSession transfers. Views observe task snapshots and submit typed commands. Persist task ID, attempt ID, accepted metadata, actual quality, effective network policy and intended destination before enqueueing a native task.

Use a fixed session identifier per effective transport-policy configuration, with a bounded set of sessions rather than a session per task. A new network preference applies to new tasks; changing it does not rewrite existing transfers. Present the policy as disallowing cellular access rather than guaranteeing a literal Wi-Fi connection.

Reserve active content/actual-quality identity transactionally. Every retry creates a new attempt. Native correlation identity and attempt checks reject delayed callbacks. Serialize short state transitions; move long file effects outside that lane with explicit task ownership and revalidate before committing. Observe events before obtaining snapshots, and reconcile database records, system tasks and real files at launch and foreground entry. Ambiguous enqueue outcomes become interrupted instead of causing duplicate transfers.

The principal task path is queued, transferring, publishing, then completed. Paused, cancelled, interrupted, transfer failure, publication failure and missing-file outcomes remain explicit. Resume data is optional and may become invalid; the UI must offer restart when safe continuation is unavailable. Unknown size remains unknown. Batch operations accept at most 100 distinct items, recheck each attempt and report independent outcomes.

Copy or move the system temporary download into owned staging storage before its callback lifetime ends. Verify and publish from staging; only a durable final location permits completed state. Keep a recovery pointer until publication and cleanup finish. A failed move or missing directory is recoverable without automatically redownloading valid staged bytes.

iOS/iPadOS media is stored in the application's `Documents/Downloads`, visible through Files, with sharing and explicit export. Unexported files disappear on uninstall. Mac defaults to application-owned storage and permits an explicitly authorized external destination. Keep staging until an external publication succeeds; a revoked bookmark asks for renewed access without discarding staged content. Removing a terminal task record preserves its file, and deleting a file preserves its record as missing. Missing local playback never silently falls back to the network.

System scheduling is authoritative. iOS force-quit cancels background transfers and prevents automatic relaunch; reconcile and offer recovery after the next explicit launch. Closing a browser window does not stop application-owned downloads. Mac application exit captures history and drains accepted database/file commits with bounded error handling; background transfer lifecycle and relaunch integration require platform verification rather than assumptions based on iOS.

## Verification and delivery boundaries

| Layer                      | Required evidence                                                                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Domain and decoding        | Shared fixture parity, quality and filename rules, invalid IDs/URLs, date normalization, completion rules                                        |
| Repository and persistence | Temporary SQLite databases, migrations, accepted-empty snapshots, late results, concurrent edits, failed writes, history invalidation            |
| Playback                   | Controlled MP4 server, range edge cases, cancelled requests, settled restoration, retry intent, observation cleanup and bounded buffering        |
| Downloads                  | Enqueue interruption, old-attempt callbacks, duplicate reservation, invalid resume data, publication recovery, missing files and partial batches |
| iPhone/iPad UI             | Compact and regular windows, rotation/resizing, navigation restoration, dynamic text, keyboard, themes and accessibility states                  |
| Mac UI                     | Window lifecycle, focused commands, selection, settings, file authorization and player ownership                                                 |
| Device lifecycle           | Background downloads, force-quit/relaunch, PiP, interruptions, device locking and external-file access                                           |

Use Swift Testing for domain/service tests and XCTest for UI automation. Inject repositories and platform ports for previews and test fixtures; do not mock source spelling or private decomposition. Add platform build/test and formatting commands to the Apple setup guide when those commands exist. Compilation, simulator checks, physical-device checks and signed release distribution are separate claims.

Delivery order is media feasibility first, then the three platform shells and browsing/playback/history flow, followed by durable downloads, file management and full platform acceptance. This is sequencing, not an executable implementation plan.

When implementation is accepted, move durable architecture into `docs/apple.md`, setup commands into `apple/README.md`, coding conventions into `apple/AGENTS.md`, and verification ownership into the maintenance guide. Replace the temporary README design link and remove this superseded specification once those owners cover its contracts. Do not commit credentials, machine-specific paths, recordings or generated caches.

## Sources

- [Apple: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Apple: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Apple: Unsupported AVURLAsset header option](https://developer.apple.com/forums/thread/671139)
- [Apple: AVAssetResourceLoader](https://developer.apple.com/documentation/avfoundation/avassetresourceloader)
- [Apple: Background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [Apple: Background session lifecycle](<https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)>)
- [GRDB](https://github.com/groue/GRDB.swift)
- [Nuke](https://github.com/kean/Nuke)

Repository authorities: [Upstream API](../../upstream-api.md), [Web Architecture](../../architecture.md), [Flutter Architecture](../../flutter.md) and [Repository Maintenance](../../maintenance.md). These define existing contracts; the new Apple implementation must prove its own compliance.
