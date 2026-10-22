# Native Apple Architecture

The SwiftUI client in `apple/` supports iOS/iPadOS 26 and macOS 26. iPhone and iPad share an iOS application target; macOS uses AppKit and native SwiftUI windows. It connects directly to upstream programme/media services, with independent local state and no Node service requirement. Build commands and acceptance limits belong to the [Apple README](../apple/README.md).

## Ownership

| Owner                                   | Responsibility                                                                                                          |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `Apps/Shared` and platform entry points | Dependency composition, navigation, application delegates, settings windows, player presentation and native file panels |
| `SCTVCore`                              | Immutable programme/history/download values, URL and quality policies, typed states and service protocols               |
| `SCTVData`                              | Bounded metadata transport, decoding, SQLite migrations, snapshots, preferences, favourites and history                 |
| `SCTVMedia`                             | Bounded HTTP ranges, resource loading, the single AVPlayer session, playback-history recording and native AVKit views   |
| `SCTVDownloads`                         | Durable queue transitions, background sessions, staging, publication, bookmarks and file leases                         |
| `SCTVFeatures`                          | Observable page models and native SwiftUI catalogue, archive, library, downloads and settings views                     |

Features depend on core service contracts. Application roots construct concrete services; the download engine does not import GRDB. GRDB owns database transactions and Nuke owns artwork loading. Swift 6 concurrency checking applies throughout. See [Apple contribution instructions](../apple/AGENTS.md) for readability and cleanup conventions.

## Navigation and browsing

The main destinations are 栏目, 资料库 and 下载. iPhone/iPad use adaptive native tabs and navigation stacks; Mac uses a sidebar and independent detail navigation. The Mac player is a separate window backed by the same application-wide player session. Scene storage retains route IDs and archive selection; shared preferences do not own individual windows' navigation.

Catalogue and broadcast results distinguish an accepted snapshot from a pending refresh. Cached results remain visible while refreshing; explicit acceptance prevents background refresh from changing a selected date or active batch. Requests have query ownership and cancellation, while page generations independently reject stale results. Date acceptance resolves the retained selection before loading its contents. Full episodes and clips use the shared programme rules and Shanghai publication ordering.

Library content combines unfinished history, favourite programmes and history grouped by local calendar day. History keeps the newest 500 entries. Progress writes are throttled to five seconds, with immediate settled seek, pause, end and lifecycle writes. Ended playback or at least 95% of a known duration marks completion; completed entries resume from zero. Session tokens and increasing write sequences prevent an older player from overwriting a newer session or recreating deleted history.

## Persistence and requests

User SQLite storage holds preferences, favourites and history. Runtime SQLite storage holds programme snapshots and durable download records; clearing programme cache does not clear downloads or user data. Runtime caches and managed downloaded media are excluded from backup through native resource attributes. Attribute tests are not backup/restore acceptance.

Preference edits carry accepted revisions. Failed saves remain visible and retryable; a failed initial read cannot silently overwrite existing data with defaults. Metadata requests have independent header/body deadlines, a 2 MiB body limit and redirect rejection. Installation identifiers belong to metadata headers, never media requests. IDs remain strings across decoding and storage.

## Playback and files

Opening a programme starts paused. One application-wide AVPlayer owns the active session, source replacement, interruption state and cleanup. Tap-time request tokens reject older metadata resolutions. Presentation tokens protect a newer player from an older window or sheet's delayed dismissal. Local playback retains a file lease for the session and never silently falls back to an online URL.

Online playback validates the shared HTTPS media allowlist, rejects redirects and requests at most 256 KiB per range, with at most four active resource reads. The resource loader cancels reads with its owner. Unsupported AVURLAsset header options are not used. This bounded strategy still requires physical-device and production-network performance acceptance.

## Download lifecycle

Preparation resolves actual quality and safe names before reserving records. Batches contain at most 100 distinct items. SQLite enforces active content/quality uniqueness. Each task pins programme metadata, source, destination and cellular policy; later preference edits affect new tasks only. Retries receive new attempt IDs. Commands and native callbacks must match the current attempt, revision and native correlation.

Fixed background URLSession identifiers represent cellular policies. The delegate synchronously adopts temporary files into owned staging before returning. Durable staged files, failure receipts and resume references recover callback/database interruption windows. Background-event completion is acknowledged only after ordered callbacks and persistence have drained. Mac quit gives persistence and reconciliation a bounded three-second drain; durable attempts recover on the next launch if it expires. Native background sessions manage their own redirect behavior; this differs from the custom playback transport's redirect rejection.

Transfer completion enters publication, not completed. Publication validates playable media, copies to an attempt-owned partial file and atomically moves to a collision-safe final name. Staging remains until the guarded completed record is durable. Recoverable destination, resource-access or space errors retain staged bytes for publication retry. Confirmed invalid media permits a fresh transfer; an operational validation error never discards staged bytes. Attempt identity and file identity prevent replacing or deleting unrelated files.

Managed iOS files live in `Documents/Downloads` and are visible in Files. Mac uses application-owned storage by default and supports explicit external directory selection. Security-scoped bookmarks remain in native user storage; renewing access replaces the existing bookmark identity so affected tasks can recover. Playback, reveal and export retain balanced access leases throughout the operation. Missing completed files become actionable missing-file records. Removing a record preserves its file; deleting a file preserves a missing-file record. Export cancellation preserves the original media.

## Acceptance boundary

Automated package tests exercise persistence, ordering, stale-result rejection, download recovery and file ownership. Native fixture UI tests exercise catalogue/archive/settings and download-to-local-playback composition. The fixture transfer driver bypasses the system background daemon; those tests do not verify actual suspension, lock, force-quit or OS background delivery.

Minimum-OS, physical-device, accessibility and system lifecycle acceptance remain separate from compilation and package tests. Keep the [implementation plan](superpowers/plans/2026-10-22-apple-client.md) until those gates are resolved. Signing, TestFlight, App Store distribution and notarization require separate delivery work.
