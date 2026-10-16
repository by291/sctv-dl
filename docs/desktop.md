# Desktop Development

One Vue frontend runs as a Web application and a Tauri 2 desktop client. Startup selects one complete platform: Web uses the Node service; Tauri uses Rust for programme APIs, playback sessions, downloads, directories, and preferences. The macOS arm64 application has been checked with bundled assets and Node stopped. Windows, minimum macOS, and public signed distribution still need their own acceptance evidence.

Desktop targets are Windows x64 and macOS arm64 (Apple Silicon). Intel Macs are outside the supported build and release matrix.

## Commands and Prerequisites

Use the Node/pnpm versions from [README](../README.md), Rust with Cargo, and the [official platform prerequisites](https://v2.tauri.app/start/prerequisites/). The generated Cargo manifest declares Rust 1.90; the native phases were built with Rust 1.98.0. The declared minimum compiler has not been separately tested.

Run from the repository root:

```sh
pnpm desktop:dev
pnpm desktop:build
```

Development starts Vite on port 5180 for frontend assets and HMR. Inside Tauri, business requests use native commands even during development. Production bundles `dist/` with Tauri's default asset protocol and needs no Node process. The browser uses history routes; desktop uses hash routes so navigation and reloads retain the bundled entry document.

To build only a local macOS application bundle:

```sh
pnpm desktop:build --bundles app
```

The output is under `src-tauri/target/release/bundle/`. macOS builds use an ad-hoc signature for local validation; they are not notarized public releases. The proposed macOS minimum is 13.0. Windows configuration selects the NSIS installer. Windows builds and runtime behaviour remain unverified in this batch.

Run the portable combined check with `pnpm desktop:check`, or run Rust checks independently:

```sh
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked
```

Native tests cover programme normalization/HTTP, cancellation, command permissions, installation-identity/directory persistence, media streaming/lifecycle, and downloads. HTTP tests use disposable local Axum stubs. Axum and Hyper implement the media-only HTTP transport described below; normal native startup binds its private loopback listener. Native build products and generated schemas are ignored. Application icons are generated from `public/favicon.svg` with `pnpm tauri icon public/favicon.svg`; keep only the desktop icon outputs when regenerating them.

## Native Module Ownership

The native implementation uses concrete services composed in `lib.rs`. The [native instructions](../src-tauri/AGENTS.md) describe readability, synchronization, and resource ownership conventions. Rustfmt owns mechanical formatting; logical phases and ownership comments remain part of review.

| Module                                 | Responsibility                                                                            |
| -------------------------------------- | ----------------------------------------------------------------------------------------- |
| `commands/`                            | Tauri arguments, managed State, Channel subscriptions, and command results.               |
| `application/`                         | Workflows that coordinate programme preparation, directory selection, and task admission. |
| `programmes/`                          | Upstream metadata normalization, broadcast lookup, and pure video selection rules.        |
| `downloads/manager.rs`                 | Admission, task state and revisions, dispatch, subscriptions, and shutdown.               |
| `downloads/worker.rs`                  | HTTP transfer, progress, writer completion, finalization, and terminal outcome.           |
| `downloads/files.rs` and `filename.rs` | File reservation/recovery ownership and pure filename policy, respectively.               |
| `media/`                               | Playback sessions and their private streaming transport, connections, and producers.      |
| `settings/`                            | Store ownership, validation, serialized persistence, and directory selection.             |
| `lifecycle/`                           | Exit coordination plus shell-specific dialog, menu, and platform integration.             |
| `requests.rs` and `error.rs`           | Request cancellation ownership and typed errors with private diagnostics.                 |

Commands preserve the `{code, message}` error response. Native code uses a closed set of error codes and retains internal causes outside serialization. Operational failures are reported at their owning boundary; expected cancellation is quiet. Reqwest causes must have their URL removed before retention so media tokens and query values do not enter diagnostics.

## Current Integration Boundary

- `shared/contracts/` contains application DTO schemas and inferred types shared by browser and Node. `shared/fixtures/` contains normalization examples consumed by both Node and Rust tests.
- `src/shared/platform/` defines injectable programme, playback, download, and settings ports. Components consume ports; native API imports in Vue components are rejected by ESLint.
- `src/platform/create-platform.ts` calls the official `isTauri()` detector once and dynamically imports the complete Web or native factory. Native initialization errors use the recoverable startup screen; startup never silently substitutes Web business services.
- Node exposes normalized `/client-api/v1` routes alongside the preserved `/api` and `/media` proxies. See [Upstream API](upstream-api.md) for contracts and [Deployment](deployment.md) for configuration migration.
- Browser downloads still use HEAD preflight and browser handoff. Native task progress, file saving, and directory selection are implemented behind the native download port. The native shell provides the task drawer and native close/menu confirmation.

## Native Programme Commands

Rust owns `list_programmes(requestId)`, `list_programme_dates(programmeId, requestId)`, `list_programme_contents(programmeId, dateId, requestId)`, and `cancel_request(requestId)`. Commands accept string domain IDs and version-4 UUID request IDs. The application manifest and `programme-api` permission restrict them to the local `main` window. The frontend has no general HTTP, filesystem, or Store command permission.

The programme client fixes production access to `https://gw.scgchc.com`, rejects redirects, and uses the existing anonymous guest headers for metadata only. Each operation has a 20-second response-header deadline and a 30-second idle-read deadline. Rust normalizes upstream values into the same DTOs as Node; `videoStandard` maps to `smoothVideo`. The TypeScript adapter validates command results, bridges `AbortSignal`, removes listeners after terminal results, and rejects cancelled requests even if IPC resolves late. Existing `LatestRequest` guards remain in the shared archive flow.

Before exposing services, startup loads a private `desktop.json` using the [official Tauri Store plugin](https://v2.tauri.app/plugin/store/), validates or creates `installationId`, and explicitly saves it. Concurrent requests then share the immutable identity. This value is separate from shared preferences. Read/write failures surface as `storage` command errors without using an ephemeral identity or terminating the shell. Invalid UUID fields are repaired while unrelated values are retained; unreadable/corrupt files are preserved and reported. Failed stores are unregistered so the plugin cannot overwrite them during its exit-time save.

Cancellation drops pending native HTTP/body futures. Cancellation that precedes registration is retained for at most 60 seconds, with a maximum of 1,024 unique markers. Registration consumes its marker; dropping or completing a request releases its active entry. No production command accepts a test origin or timeout override.

## Native Playback and Media Transport

`src-tauri/src/media/` implements a Rust-owned, media-only HTTP service. It binds `127.0.0.1` on an OS-assigned port. Rust registers validated sources under unpredictable session tokens; HTTP callers cannot supply an upstream URL. Default production policy allows only HTTPS MP4 files on `fscgc.scgchc.com`, with no credentials or nondefault port. Redirects are rejected. Media requests insert only the media Referer and forward Range/If-Range; guest headers, cookies, and authorization are not forwarded.

The service handles GET, HEAD, and OPTIONS, validates Host and any supplied Origin, and preserves media response headers including 206/416 ranges. Headers have a 20-second deadline; upstream reads have a 30-second idle deadline with no whole-video timeout. A capacity-one channel applies backpressure. Its producer owns the upstream response independently of downstream body polling, so session cancellation releases upstream work even when the player stops reading. Shutdown stops the listener, cancels sessions, terminates owned HTTP connections, and waits for the tracked producers, including work behind stalled clients.

`open_playback(request, requestId)` accepts programme/date/content IDs and quality. Rust resolves the selected date/content, validates available sources, applies quality fallback, and returns an opaque session URL per variant. `close_playback(sessionId)` is idempotent. The local-main-window `playback-api` capability grants these commands; callers cannot register arbitrary upstream URLs.

The shared preview opens sessions through `PlaybackPort`, shows loading/error/retry states, and cancels superseded work. A session arriving after cancellation or malformed IPC validation is closed. Closing pauses immediately and releases the player/session after the modal leave animation; reopening cannot be cleared by an old callback. Artplayer's quality switch retains playback time. PiP checks both the standard and WebKit APIs; fullscreen checks the active WebView's support.

The current custom-protocol response API requires complete response bodies, so the implementation selects streaming loopback HTTP. This implementation decision is separate from release acceptance: Windows WebView2 and complete process-memory measurements remain unverified. CSP permits loopback URLs only for media; metadata and player controls remain IPC. Frontend assets use the normal Tauri protocol, without the Localhost plugin.

## Native Downloads

Rust exposes `start_downloads(request)`, `list_downloads()`, `subscribe_downloads(onEvent)`, `unsubscribe_downloads(subscriptionId)`, `cancel_download(taskId)`, `get_download_directory()`, and `choose_download_directory()`. The `download-api` permission grants these commands only to the local main window. Direct frontend Dialog, Store, and filesystem commands remain unavailable. Requests contain programme/date/content IDs and quality; Rust fetches the matching records, validates media policy, applies quality fallback, and derives filenames. Failures remain independent per content item.

The manager reuses Tokio's bounded `mpsc`, `Semaphore(2)`, and tokio-util's `CancellationToken`/`TaskTracker`. Default admission allows at most 102 unfinished tasks, including tasks waiting outside the channel for a concurrency permit. Excess files receive individual queue-full failures. Repeated active content/actual-quality/directory submissions reuse the existing task ID. Cancelling queued work does not wait for running downloads to finish. HTTP uses the fixed media policy, no redirects or guest headers, a 20-second header deadline, and a 30-second idle deadline. Filesystem reservation runs outside the task-state mutex, so listing and cancelling tasks remain responsive while a directory is slow. Progress events are limited to one every 100 ms per task; state/terminal updates are immediate. Unknown totals stay `null`.

The [official Dialog plugin](https://v2.tauri.app/plugin/dialog/) selects a directory in Rust when none is saved. Cancelling creates no tasks. Selection is serialized and the directory is saved privately in `desktop.json`; a removed or inaccessible saved location fails explicitly. Failed saves restore the previous in-memory directory and report a storage error. The manager validates the directory again when starting work.

Each destination directory has a small `.sctv-dl.lock` ownership marker, retained after exit. An OS file lock prevents another desktop instance from recovering active artifacts there. Tasks reserve case-insensitive unique names and write UUID-specific `.part` files, with matching versioned `.json` recovery records. File names handle Windows devices/invalid characters and Unicode truncation; overly long directory paths fail with a request to choose a shorter location.

Flush, sync, and writer closure precede no-clobber finalization. A retained file identity handle protects live reservations from publishing or deleting a replacement at the temporary path; queued jobs retain only that handle. Existing files retain their bytes, including when a competing destination appears during transfer. Cancellation/failure removes owned temporary files and reservations; cleanup failures surface in task errors. A handled replacement is preserved and its owned journal removed so the next open cannot recover it. Acquisition establishes file identity before a fallible writer clone or initialization write. Failures remove newly owned artifacts and report cleanup failures. If identity itself cannot be established, the path is preserved and reported for inspection rather than deleted without proof of ownership.

After a process interruption, recovery treats an exact versioned UUID record plus its matching regular temporary path as an owned pair; it has no live file identity handle. Unknown files and records remain untouched.

The TypeScript adapter validates command/channel payloads. The shared download store subscribes before requesting its snapshot and merges monotonic revisions, preserving terminal events that arrive during hydration. Its desktop-only task drawer remains in the application shell across page navigation, shows received bytes/unknown totals, and offers cancel/retry. Retry uses the content reference and actual quality. Preparation failures remain visible in the drawer. The drawer loads lazily, so Web startup does not load its UI chunk.

Task history is limited to the current process; no restart resume is implemented. Application exit stops admission and awaits blocking directory preparation, transfer cancellation, and file cleanup before releasing directory locks. Rust coordinates close/menu confirmation and pending native operations as described below. Installed Windows behaviour is still unverified; the macOS probe and automated evidence are recorded below.

## Preferences and Exit Integration

`load_settings()` and `save_settings(value)` expose only quality, theme, and favourite string IDs to the local main window under `settings-api`. Rust normalizes the same defaults as the shared schema, limits save payloads to 16 KiB, and preserves private identity/directory values. Native read failures return usable defaults with `persisted: false`; write failures propagate and roll back Store memory. The settings service privately owns its Store and shared write mutex. Filesystem validation, persistence, and blocking lock waits run in `spawn_blocking`; the native folder picker stays asynchronous. The Store plugin's direct filesystem write is not claimed to be atomic after a partial OS write.

The native settings adapter validates snapshots. The shared settings store subscribes before load, preserves newer edits and subscription updates, serializes saves, ignores older save echoes while writes are pending, and detaches on disposal. Both platforms hydrate their selected settings port before mounting; an unexpected startup failure offers retry. The directory UI is native-only and retains browser-managed copy for Web. Its operation revisions reject stale directory responses, and picker cancellation rechecks the saved location so an unresolved error stays visible.

The native exit controller first stops new download/picker/playback preparation, then requests a frontend acknowledgement through a Tauri Channel. The settings store drains its serialized save queue, including edits added while a save is pending. Rust permits those saves during preparation, then freezes admission and waits for existing native operations before taking the final task snapshot. A failed acknowledgement or a five-second timeout asks before discarding unsaved settings. Active downloads also require confirmation. Rejecting reopens admission; accepting cancels and awaits file cleanup before exiting. Repeated requests share one attempt. Blocking writes retain their operation guard even if an IPC future is dropped.

Menus retain Tauri's standard application/edit/window structure and ordinary decorations. The predefined Quit item is replaced through the official menu API because macOS otherwise invokes `terminate:` without cancellable `ExitRequested`. The replacement retains the platform label and shortcut. A small macOS-only bridge through `objc2` and AppKit adds the missing `applicationShouldTerminate:` delegate method and forwards Dock/system Quit to the same controller. It preserves the existing TAO delegate and refuses to replace an existing method. Unit coverage checks installation; interactive Dock verification was unavailable because the UI automation server timed out inspecting Dock. Main-window close and menu/shortcut confirmation passed installed-app checks. Confirmation is parented to the main window. Force/process termination relies on recognized-leftover recovery.

## CI and Distribution

[Desktop validation](../.github/workflows/desktop.yml) builds Windows x64 on `windows-2025` and Apple Silicon on `macos-15`. It runs Web and Cargo checks, uses frozen lockfiles and shared pnpm/Rust caches, and uploads NSIS/DMG validation artifacts for 14 days with read-only repository permissions. macOS DMGs contain the application bundle. Actions are pinned to commit SHAs. These workflows were prepared locally; no remote CI run is claimed.

[Desktop release](../.github/workflows/desktop-release.yml) is manually triggered with an existing tag matching the package, Tauri, and Cargo versions. A source job resolves the fully qualified tag once, checks its commit against HEAD, and pins every platform build to that SHA. A same-named branch cannot substitute for the tag; the tag is rechecked before building and public promotion. It requires signing credentials, builds every target into a draft release through the official Tauri action, and publishes only when the explicit `publish` input is true and all builds succeed. A default run stays draft. No workflow was dispatched or release published in this implementation session.

Windows secrets are `WINDOWS_CERTIFICATE` (base64 PFX) and `WINDOWS_CERTIFICATE_PASSWORD`. A temporary PFX is imported into the runner's user certificate store, its thumbprint configures Tauri's native signer, and the PFX/certificate/configuration are removed afterward. macOS requires `APPLE_CERTIFICATE` (base64 P12), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`, and `APPLE_TEAM_ID`; Tauri handles certificate import and notarization. Missing credentials fail instead of falling back to unsigned public packages. Public distribution still requires operator review of installed-app evidence and signing/notarization results.

Keep build evidence, interactive OS/architecture acceptance, signing, and publication separate. Proposed Windows 10/11 x64 and macOS 13+ on Apple Silicon support remains a target until tested on those systems. See [validation evidence](desktop-media-validation.md) for the actual host, checks, and remaining limits.
