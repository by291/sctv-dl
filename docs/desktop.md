# Desktop Development

One Vue frontend runs as a Web application and a Tauri 2 desktop client. Startup selects one complete platform: Web uses the Node service; Tauri uses Rust for programme APIs, playback sessions, downloads, directories, and preferences. Production bundles frontend assets and uses native services without a project Node process. This guide owns Tauri integration, native resource contracts, packaging and release checks.

Desktop targets are Windows x64 and macOS arm64 (Apple Silicon). Intel Macs are outside the supported build and release matrix.

## Commands and Prerequisites

Use the Node/pnpm versions from [README](../README.md), Rust with Cargo, and the [official platform prerequisites](https://v2.tauri.app/start/prerequisites/). Use `src-tauri/Cargo.toml` and `Cargo.lock` for the compiler requirement and resolved Rust dependencies. CI checks the declared Rust 1.90 minimum on both desktop hosts with locked dependencies and all Rust targets. The main formatting, Clippy, test and packaging toolchain remains pinned separately. Locally, install the minimum with `rustup toolchain install 1.90.0 --profile minimal`, then run `cargo +1.90.0 check --manifest-path src-tauri/Cargo.toml --all-targets --locked` from the repository root. Compiler checks do not establish minimum-OS runtime support.

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

The output is under `src-tauri/target/release/bundle/`. macOS builds use an ad-hoc signature for local validation; they are not notarized public releases. Windows configuration selects the per-user NSIS installer. Windows 10/11 x64 and macOS 13+ on Apple Silicon are release targets; verify the minimum OS versions separately.

### Windows Installer Customization

`src-tauri/tauri.windows.conf.json` selects Simplified Chinese, per-user installation, and the application's icon and bitmap artwork. `src-tauri/windows/installer-hooks.nsh` supplies concise welcome, directory, completion, and uninstall text using NSIS Modern UI settings. `SimpChinese.nsh` supplies Tauri-specific messages and the Windows UI font. The stock Tauri template continues to own WebView2 setup, upgrades, shortcut ownership checks, and uninstall registration; no copied installer template is maintained.

`installer-ui.nsh` sets both window icon sizes, aligns header text, adds native sidebar lettering, and positions optional data removal at the bottom of the uninstall page. The bitmap artwork has four times its base resolution; the header keeps its complete brand artwork in one bitmap to avoid overlapping MUI controls. Welcome and finish use native text over the sidebar graphic. Two small page-entry wrappers attach show callbacks to MUI's existing finish and uninstall page implementations; the uninstall callback first calls Tauri's original checkbox setup, retaining its default state and leave handler. Recheck these wrappers when upgrading NSIS/Tauri. See the [MUI callback reference](https://nsis.sourceforge.io/Docs/Modern%20UI%202/Readme.html) for lifecycle ordering. Fonts and icons created by the hooks are released when the wizard closes.

The uninstaller's application-data checkbox remains unchecked by default. Retaining data preserves settings, favourites, history, and programme cache. Selecting it clears the two private application-data directories after Tauri checks that the application has stopped. Cleanup does not traverse directory links or directories containing the native download ownership marker, including download destinations nested inside private data. It never follows the saved video directory. Preserved or undeletable directories are reported. Installation-only registry values are removed independently of that checkbox, but preserved during upgrades or when the registered location belongs to a different installation. Unknown registry values remain untouched.

On Windows, regenerate the bitmap artwork and uninstaller icon with `pwsh -NoProfile -File tooling/generate-installer-artwork.ps1`. The bitmaps use the existing application icon. Tauri renders `src-tauri/windows/uninstaller.svg` into a multi-size ICO with a grey television and red minus badge; this icon is used for both the uninstaller executable and its window. The application and setup retain the red television icon. Build with `pnpm desktop:build`; when only installer inputs change and the release executable is current, repackage with `pnpm tauri bundle --bundles nsis`.

After the first Windows bundle has provisioned NSIS, run `pwsh -NoProfile -File tooling/check-windows-installer.ps1`. Pass `-NsisDirectory` for another NSIS installation. The test compiles and executes a silent native fixture using the production cleanup macros, verifies actual registry results for normal uninstall, upgrade, unrelated values, and stale installations, and checks private-data removal while preserving external/nested downloads and directory junctions. It removes its uniquely named fixtures afterward. Windows desktop CI runs it after bundling. This fixture does not replace interactive installer/uninstaller acceptance.

Run the portable combined check with `pnpm desktop:check`, or run Rust checks independently:

```sh
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked
```

`pnpm desktop:check` supplies `CARGO_BUILD_JOBS` only to its Cargo child processes, defaulting to four jobs or the available parallelism when lower. This limits concurrent Clippy compilation and test linking on high-core machines. An existing `CARGO_BUILD_JOBS` is preserved unchanged; Cargo owns value parsing and validation. The environment setting takes precedence over `build.jobs` in Cargo configuration files. The script does not change the parent environment or the defaults for `desktop:dev`, `desktop:build`, or standalone Cargo commands.

Native tests cover programme normalization/HTTP, cancellation, command permissions, installation-identity/directory persistence, media streaming/lifecycle, and downloads. HTTP tests use disposable local Axum stubs. Axum and Hyper implement the media-only HTTP transport described below; normal native startup binds its private loopback listener. Native build products and generated schemas are ignored. Application icons are generated from `public/favicon.svg` with `pnpm tauri icon public/favicon.svg`; keep only the desktop icon outputs when regenerating them.

## Native Module Ownership

The native implementation uses concrete services composed in `lib.rs`. The [native instructions](../src-tauri/AGENTS.md) describe readability, synchronization, and resource ownership conventions. Rustfmt owns mechanical formatting; every changed function and macro also needs a manual review of logical paragraphs and ownership comments. Normalized cache DTOs alias programme models, while cache payload validation retains its separate input checks. History and download modules reexport `ContentRef` for compatibility.

| Module                                                | Responsibility                                                                                                                      |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `lib.rs` and `application/bootstrap.rs`               | Plugin/command registration and concrete service initialization, degraded modes, and window restoration.                            |
| `commands/`                                           | Tauri arguments, managed State, Channel subscriptions, and command results.                                                         |
| `application/downloads.rs` and `download_files.rs`    | Start/action coordination, lifecycle admission, refreshed programme sources, directory selection, and native opener adaptation.     |
| `programmes/`                                         | Upstream normalization, programme-owned `ContentRef` and normalized DTOs, broadcast lookup, and pure video selection rules.         |
| `downloads/manager.rs` and `actions.rs`               | Initial/retry admission and dispatch, task actions, directory ownership, and shutdown.                                              |
| `downloads/records.rs`                                | Task records and controls, shared capacity/deduplication rules, serialized commits, revisions, progress merging, and subscriptions. |
| `downloads/recovery.rs`                               | Startup reconciliation between task records, checkpoints, and completed publications.                                               |
| `downloads/worker.rs`                                 | HTTP negotiation and transfer, writer settlement, checkpoints, publication, and terminal outcomes.                                  |
| `downloads/files.rs` and `files/`                     | Directory locking/reservation, early artifact rollback, recognized recovery, and identity-checked no-clobber publication.           |
| `downloads/filename.rs`, `resume.rs`, and `errors.rs` | Portable names, pure resume validation, and private primary/cleanup error preservation.                                             |
| `media/`                                              | Playback sessions, private streaming transport, connections, and independently owned local/upstream producers.                      |
| `history/`                                            | Session/sample ownership, bounded history persistence, and committed snapshot publication.                                          |
| `programme_cache/`                                    | Cache service/state, manifest validation/access/eviction, and disk read/commit/cleanup policy in separate modules.                  |
| `settings/`                                           | Store ownership, validation, serialized persistence, and directory selection.                                                       |
| `lifecycle/`                                          | Exit coordination plus shell-specific dialog, menu, and platform integration.                                                       |
| `requests.rs` and `error.rs`                          | Request cancellation ownership and typed errors with private diagnostics.                                                           |

Commands preserve the `{code, message}` error response. Native code uses a closed set of error codes and retains internal causes outside serialization. Operational failures are reported at their owning boundary; expected cancellation is quiet. Reqwest causes must have their URL removed before retention so media tokens and query values do not enter diagnostics.

## Current Integration Boundary

- `shared/contracts/` contains application DTO schemas and inferred types shared by browser and Node. `shared/fixtures/` contains normalization examples consumed by both Node and Rust tests.
- `src/shared/platform/` defines injectable programme, playback, download, settings, history, and programme-cache ports. Components consume ports; native API imports in Vue components are rejected by ESLint.
- `src/platform/create-platform.ts` calls the official `isTauri()` detector once and dynamically imports the complete Web or native factory. Native initialization errors use the recoverable startup screen; startup never silently substitutes Web business services.
- Node exposes normalized `/client-api/v1` routes alongside the preserved `/api` and `/media` proxies. See [Upstream API](upstream-api.md) for contracts and [Deployment](deployment.md) for configuration migration.
- Browser downloads still use HEAD preflight and browser handoff. Native task progress, file saving, and directory selection are implemented behind the native download port. The native shell provides download navigation, persistent task observation, and native close/menu confirmation.

## Native Programme Commands

Rust owns `list_programmes(requestId)`, `list_programme_dates(programmeId, requestId)`, `list_programme_contents(programmeId, dateId, requestId)`, and `cancel_request(requestId)`. Commands accept string domain IDs and version-4 UUID request IDs. The application manifest and `programme-api` permission restrict them to the local `main` window. The frontend has no general HTTP, filesystem, or Store command permission.

The programme client fixes production access to `https://gw.scgchc.com`, rejects redirects, and uses the existing anonymous guest headers for metadata only. Each operation has a 20-second response-header deadline and a 30-second idle-read deadline. Rust normalizes upstream values into the same DTOs as Node; `videoStandard` maps to `smoothVideo`. The TypeScript adapter validates command results, bridges `AbortSignal`, removes listeners after terminal results, and rejects cancelled requests even if IPC resolves late. Existing `LatestRequest` guards remain in the shared archive flow.

Before exposing services, startup loads a private `desktop.json` using the [official Tauri Store plugin](https://v2.tauri.app/plugin/store/), validates or creates `installationId`, and explicitly saves it. Concurrent requests then share the immutable identity. This value is separate from shared preferences. Read/write failures surface as `storage` command errors without using an ephemeral identity or terminating the shell. Invalid UUID fields are repaired while unrelated values are retained; unreadable/corrupt files are preserved and reported. Failed stores are unregistered so the plugin cannot overwrite them during its exit-time save.

Cancellation drops pending native HTTP/body futures. Cancellation that precedes registration is retained for at most 60 seconds, with a maximum of 1,024 unique markers. Registration consumes its marker; dropping or completing a request releases its active entry. No production command accepts a test origin or timeout override.

## Native Playback and Media Transport

`src-tauri/src/media/` implements a Rust-owned, media-only HTTP service. It binds `127.0.0.1` on an OS-assigned port. Rust registers validated sources under unpredictable session tokens; HTTP callers cannot supply an upstream URL. Playback and downloads share an explicit production allowlist for HTTPS MP4 files on `fscgc.scgchc.com` and `fscgc.sctv-tf.com`, with no credentials or nondefault port. Internal test configurations replace that list with their stub origins. Redirects are rejected. Metadata, native playback and downloads share `User-Agent: okhttp/4.12.0` from `src-tauri/src/upstream.rs`. The historical CDN rejects requests without a client identifier. Media requests add the media Referer and forward Range/If-Range; guest headers, cookies, authorization, and the WebView's User-Agent are not forwarded.

The service handles GET, HEAD, and OPTIONS, validates Host and any supplied Origin, and preserves media response headers including 206/416 ranges. Headers have a 20-second deadline; upstream reads have a 30-second idle deadline with no whole-video timeout. A capacity-one channel applies backpressure. Its producer owns the upstream response independently of downstream body polling, so session cancellation releases upstream work even when the player stops reading. Shutdown stops the listener, cancels sessions, terminates owned HTTP connections, and waits for the tracked producers, including work behind stalled clients.

`open_playback(request, requestId)` accepts programme/date/content IDs and quality. Rust resolves the selected date/content, validates available sources, applies quality fallback, and returns an opaque session URL per variant. `close_playback(sessionId)` is idempotent. The local-main-window `playback-api` capability grants these commands; callers cannot register arbitrary upstream URLs.

The shared preview opens sessions through `PlaybackPort`, shows loading/error/retry states, and cancels superseded work. A session arriving after cancellation or malformed IPC validation is closed. Closing pauses immediately and releases the player/session after the modal leave animation; reopening cannot be cleared by an old callback. Artplayer's quality switch retains playback time. PiP checks both the standard and WebKit APIs; fullscreen checks the active WebView's support.

The current custom-protocol response API requires complete response bodies, so the implementation selects streaming loopback HTTP. CSP permits loopback URLs only for media; metadata and player controls remain IPC. Frontend assets use the normal Tauri protocol, without the Localhost plugin.

## Native Downloads

Rust exposes reference-based download preparation, revisioned snapshots/events, attempt-checked actions, directory selection, and local playback. `get_download_snapshot`, `subscribe_download_events`, and `act_on_download` carry the shared contracts; legacy list/cancel subscriptions remain available. The local-main-window capability never grants general frontend filesystem or Opener access. The Rust Opener plugin receives only paths resolved from validated task records.

The manager uses a bounded Tokio queue with two concurrent transfers. Initial and retry admission share capacity and unfinished content/actual-quality/directory deduplication rules. Task records commit acceptance and install cancellation ownership before dispatch. Their writer gate serializes disk changes; short state locks keep progress observable during I/O, and commit revisions follow any progress published during that I/O. Tasks retain stable IDs across resume and redownload, with a new attempt ID for each transfer. A process epoch plus monotonic revisions lets the frontend merge snapshots and events without resurrecting removed tasks or accepting callbacks from an old attempt. Preparation failures remain independent per file.

`downloads-v1.json` stores tasks and pinned programme metadata under the application data directory. Atomic replacement and an OS index lock protect persistence; corrupt or locked indexes disable downloads while the rest of the application remains usable. Task records contain private native paths, never frontend-provided paths. Each destination also retains an OS-locked `.sctv-dl.lock` marker. UUID-specific `.part` files have version-2 journals containing file identity, attempt identity, committed bytes, total size, strong ETag, and publication phase. Unknown files and legacy artifacts are preserved.

Pause stops transfer I/O, flushes and syncs the writer, then records a checkpoint. Recovery validates journal/index ownership and file identity, trims bytes beyond the committed boundary, and marks unfinished work interrupted without starting network transfers. Resume resolves a fresh URL using the saved content IDs and actual quality; URLs are not durable identities. It sends Range and If-Range and appends only when a strong ETag, total size, exact range start, and local length all match. A full response, changed validator, malformed range, or unavailable representation requires explicit redownload. A matching 416 at the exact total can finalize an already complete file.

Finalization records publication intent, closes the writer, and publishes without replacing an existing destination. Cancellation deletes only proven-owned partial artifacts. Failure preserves useful partial data; files whose identity cannot be established remain untouched and are reported. Replaced files, symlinks, and unknown recovery records are never deleted as owned downloads. Rollback takes ownership immediately after artifact creation, before handle cloning or journal initialization can fail. Explicit cleanup retains both a primary failure and a later cleanup/rollback failure; `Drop` supplies best-effort fallback. A replaced task index remains authoritative even if its parent-directory sync fails, so its reservation cannot be discarded as an uncommitted attempt.

The task page provides status filters, pause/continue/redownload/cancel, and batch actions. Confirmation captures task IDs and attempt IDs; each item is revalidated immediately before execution, and the result distinguishes applied, skipped, and failed actions. Removing a completed record leaves its file; deleting a file retains a missing-file record. These operations have separate confirmation copy. Opening a file or revealing its folder is resolved and validated in Rust.

Completed files can play in the shared preview without contacting upstream. `open_local_playback` opens a verified regular file handle and returns an opaque private-loopback session; the transport supports bounded streaming, HEAD, and Range. Removing a file first revokes its associated playback URLs and awaits every admitted local reader. URL closure signals cancellation; task-level reader ownership survives that closure and cancellation of a previous waiter. A blocking positional read must finish before its producer releases the opened handle, even if its IPC/HTTP caller disappears. Service shutdown also awaits these retired producers. Concurrent Range requests retain independent cursors. Missing or replaced files show a local error; local playback does not silently switch to an online source. Preview cleanup still follows the modal leave animation.

Exit pauses active durable tasks and awaits checkpoints before releasing directory ownership. A checkpoint failure offers a separate force-exit decision; returning to the application restores admission and preserves artifacts. Restart does not automatically resume paused/interrupted work. Browser downloads remain browser-managed handoffs and do not appear in this native queue.

## History and Programme Cache

Both platforms expose the same history and programme-cache ports. Native history uses a dedicated versioned file with serialized atomic writes, session tokens, and monotonic samples. It retains 500 entries and reports non-durable writes without discarding the current visible position. Removing or clearing entries invalidates old session ownership, including after a replacement succeeded but directory sync failed. The browser equivalent uses IndexedDB with transactional ownership and cross-tab invalidation.

Native metadata cache files use a generation manifest, with at most 200 snapshots, 20 MiB of UTF-8 snapshot data, and 100 archive browsing records. Snapshot files commit before their manifest entries. Manifest persistence distinguishes unchanged, replaced-but-not-confirmed-durable, and durable outcomes: an already replaced manifest becomes authoritative even when its parent-directory sync fails, and cleanup follows replacement. An unchanged candidate leaves the retained manifest and its durability intact. Browse edits adopted in memory remain non-durable until the full index commits; memory-only snapshots independently report `persisted: false`, including stale-epoch replies. A successful retry clears the relevant warning without confusing warning text with persistence state.

Missing/corrupt snapshots can be dropped from the index; a transient I/O error preserves the reference for retry. An unreadable manifest remains untouched and disables writes for that owner while retaining its process lock. Corrupt manifest content starts a fresh generation without rediscovering old snapshots. Clear commits a new generation before cleanup; in-flight old-generation writes cannot recreate the cache. Cache data contains catalogue/date/content metadata and date/sort/scroll preferences, never downloaded video. Snapshot display and accepted/pending refresh behavior are shared with Web; see [Architecture](architecture.md).

## Preferences and Exit Integration

The main window uses the official [window-state plugin](https://v2.tauri.app/plugin/window-state/) to remember its normal size, position, and maximized state. Move/resize events update the plugin's in-memory state, and actual application exit persists it to `.window-state.json` in the application configuration directory. Cancelling an exit attempt keeps the window and tracking active. The main window is created hidden. Setup explicitly restores its state before showing it, and the plugin skips its automatic initial restore to prevent a second move after display. A restoration error is logged but does not suppress showing the window. Hidden and fullscreen states are not restored. First launch or an unreadable state file uses the configured 1200-by-820 default; a saved position outside all available monitors is skipped so the OS can place the window on the current display. Windows application configuration lives under the same private Roaming directory covered by optional uninstall data cleanup.

`load_settings()` and `save_settings(value)` expose only quality, theme, and favourite string IDs to the local main window under `settings-api`. Rust normalizes the same defaults as the shared schema, limits save payloads to 16 KiB, and preserves private identity/directory values. Native read failures return usable defaults with `persisted: false`; write failures propagate and roll back Store memory. The settings service privately owns its Store and shared write mutex. Filesystem validation, persistence, and blocking lock waits run in `spawn_blocking`; the native folder picker stays asynchronous. The Store plugin's direct filesystem write is not claimed to be atomic after a partial OS write.

The native settings adapter validates snapshots. The shared settings store subscribes before load, preserves newer edits and subscription updates, serializes saves, ignores older save echoes while writes are pending, and detaches on disposal. Both platforms hydrate their selected settings port before mounting; an unexpected startup failure offers retry. The directory UI is native-only and retains browser-managed copy for Web. Its operation revisions reject stale directory responses, and picker cancellation rechecks the saved location so an unresolved error stays visible.

The native exit controller first stops new download/picker/playback preparation, then requests a frontend acknowledgement through a Tauri Channel. The frontend captures current playback progress and drains both history and settings queues, including writes issued while a save is pending. Rust permits those saves during preparation, then freezes admission and waits for existing native operations before taking the final task snapshot. A failed acknowledgement or a five-second timeout asks before discarding unsaved settings or viewing progress. Active downloads also require confirmation. Rejecting reopens admission; accepting pauses downloads and awaits durable checkpoints before exiting. Failed checkpoints require a separate force-exit confirmation. Repeated requests share one attempt. Blocking writes retain their operation guard even if an IPC future is dropped.

Menus retain Tauri's standard application/edit/window structure and ordinary decorations. The predefined Quit item is replaced through the official menu API because macOS otherwise invokes `terminate:` without cancellable `ExitRequested`. The replacement retains the platform label and shortcut. A small macOS-only bridge through `objc2` and AppKit adds the missing `applicationShouldTerminate:` delegate method and forwards Dock/system Quit to the same controller. It preserves the existing TAO delegate and refuses to replace an existing method. Confirmation is parented to the main window. Force/process termination relies on recognized-leftover recovery.

## CI and Distribution

[Desktop validation](../.github/workflows/desktop.yml) builds Windows x64 on `windows-2025` and Apple Silicon on `macos-15`. It runs focused platform/IPC/release-source tests, Cargo checks and frontend compilation, uses frozen lockfiles and shared pnpm/Rust caches, and uploads NSIS/DMG validation artifacts for 14 days with read-only repository permissions. macOS DMGs contain the application bundle. Actions are pinned to commit SHAs. Documentation-only and mobile-only changes skip desktop builds; the common Ubuntu workflow owns repository lint/format/link checks and the complete Web/server test suite. See [Repository Maintenance](maintenance.md) for trigger ownership.

[Desktop release](../.github/workflows/desktop-release.yml) is manually triggered with an existing tag matching the package, Tauri, and Cargo versions. A source job resolves the fully qualified tag once, checks its commit against HEAD, and pins every platform build to that SHA. A same-named branch cannot substitute for the tag; the tag is rechecked before building and public promotion. It requires signing credentials, builds every target into a draft release through the official Tauri action, and publishes only when the explicit `publish` input is true and all builds succeed. The Windows matrix runs the installer-cleanup regression after packaging; any failure prevents the publish job. A default run stays draft.

`tooling/desktop-release.ts` keeps source/version checks dependency-free because CI runs them before `pnpm install`. It validates JSON version fields and reads Cargo's explicit `[package]` version independently of dependency table order. Configuration failures identify the source file.

Windows secrets are `WINDOWS_CERTIFICATE` (base64 PFX) and `WINDOWS_CERTIFICATE_PASSWORD`. `tooling/windows-signing.ps1 -Mode Prepare` imports a temporary PFX into the runner's user certificate store. Its thumbprint configures Tauri's native signer. The script attempts temporary PFX removal on every path and rolls back signing identities reported by the importer when setup fails. Cleanup failures are reported without replacing an existing setup failure. The workflow calls `-Mode Cleanup` after the build and removes the generated configuration in a separate always-run step. The temporary release configuration is ignored by Git. macOS requires `APPLE_CERTIFICATE` (base64 P12), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`, and `APPLE_TEAM_ID`; Tauri handles certificate import and notarization. Missing credentials fail instead of falling back to unsigned public packages. Public distribution still requires operator review of installed-app evidence and signing/notarization results.

Run `pwsh -NoProfile -File tooling/windows-signing.test.ps1` to exercise setup, credential rejection, configuration writes, and failure cleanup with disposable files and a stubbed certificate store. Both Windows validation and release jobs run this check before packaging. It can also run in a portable PowerShell session; it does not prove real Windows certificate import or signed output.

## Platform Diagnostics and Release Checks

- Windows MSVC executables, including Rust test harnesses, need Common Controls v6 for native dialogs. `src-tauri/build.rs` embeds the dependency through the linker and disables Tauri's duplicate application manifest. A harness failure before tests with `0xc0000139` warrants checking that manifest, not changing test assertions.
- Installer hooks must not change `$OUTDIR` or the process working directory for temporary icon extraction; use `$PLUGINSDIR` so uninstallation can remove its own directory. If Explorer shows a stale icon despite correct executable resources, compare a fresh copy and the Shell icon cache before regenerating assets.
- Validate installation/uninstallation from an ordinary user context. Packaged automation hosts can expose virtualized paths or registry views. Check actual program files, both shortcuts, registration and both data-checkbox choices; never add broad registry deletion to compensate for an observation mismatch.

Release acceptance must cover the following on each advertised OS/architecture. Automated checks and an isolated fixture cover narrower contracts than an installed application.

| Area                           | Required check                                                                                                                                                       |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Startup and routing            | Bundled assets and hash-route reloads without Node; metadata and recoverable startup failures.                                                                       |
| Playback                       | Online/local playback, forward/backward seek, quality retention, fullscreen/PiP where available, close/reopen and release of connections/readers.                    |
| Memory                         | Compare idle, sustained playback, seek/switch and post-close memory across Rust and all WebView processes; a single RSS sample is insufficient.                      |
| Downloads                      | Picker cancellation, Unicode paths, real file bytes, pause/restart/resume, failure recovery, open/reveal/delete and replacement-file protection.                     |
| Exit and persistence           | Rejected/accepted active-task exit, queued settings/history writes, failed checkpoints, native menu and macOS Dock/system Quit.                                      |
| Window state and accessibility | Normal/maximized bounds, minimized exit, removed monitors, corrupt/missing state, narrow/large-text layouts, both themes, keyboard and native back/scroll behaviour. |
| Installer and release          | Program/shortcut/registry ownership, data retention/deletion without video loss, display scaling, real signing/notarization and minimum-OS installation.             |

Repeat installed macOS durable-download recovery/local-file actions and Windows external-file/failure-state journeys after relevant changes. Minimum OS coverage, sustained memory behaviour, Dock termination, complete window restoration and signed distribution remain acceptance work rather than implied guarantees from compilation. Keep per-run screenshots, hashes, process samples and logs with the test or release artifacts, outside this guide.
