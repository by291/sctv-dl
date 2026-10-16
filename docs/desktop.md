# Desktop Development

The repository contains a Tauri 2 shell, shared contracts/Web adapters, native programme services, a Rust media transport candidate, and native download services with a task panel. The normal application still starts with Web adapters; full native composition, playback integration, preference hydration, and exit confirmation remain later phases. It is not a complete desktop client.

## Commands and Prerequisites

Use the Node/pnpm versions from [README](../README.md), Rust with Cargo, and the [official platform prerequisites](https://v2.tauri.app/start/prerequisites/). The generated Cargo manifest declares Rust 1.90; the native phases were built with Rust 1.98.0. The declared minimum compiler has not been separately tested.

Run from the repository root:

```sh
pnpm desktop:dev
pnpm desktop:build
```

Development starts Vite on port 5180. At this stage it still uses the Web business adapters and Node middleware. Production bundles `dist/` into the application using Tauri's default asset protocol. A packaged shell can display the interface without Node, but its regular pages do not select the native adapter yet. The native command bridge has been checked separately with bundled assets and Node stopped; full startup selection remains Task 7.

To build only a local macOS application bundle:

```sh
pnpm desktop:build --bundles app
```

The output is under `src-tauri/target/release/bundle/`. macOS builds use an ad-hoc signature for local validation; they are not notarized public releases. The proposed macOS minimum is 13.0. Windows configuration selects the NSIS installer. Windows builds and runtime behaviour remain unverified in this batch.

Rust checks can be run independently:

```sh
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked
```

Native tests cover programme normalization/HTTP, cancellation, command permissions, installation-identity/directory persistence, media streaming/lifecycle, and downloads. HTTP tests use disposable local Axum stubs. Axum and Hyper are runtime dependencies for the media-only HTTP candidate described below; no media listener starts in the regular application yet. Native build products and generated schemas are ignored. Application icons are generated from `public/favicon.svg` with `pnpm tauri icon public/favicon.svg`; keep only the desktop icon outputs when regenerating them.

## Current Integration Boundary

- `shared/contracts/` contains application DTO schemas and inferred types shared by browser and Node. `shared/fixtures/` contains normalization examples consumed by both Node and Rust tests.
- `src/shared/platform/` defines injectable programme, playback, download, and settings ports. Components consume ports; native API imports in Vue components are rejected by ESLint.
- `src/platform/web-platform.ts` composes the current Web adapters. The native programme adapter exists in `programme-api.tauri.ts`, but environment selection remains Task 7 so regular startup cannot mix native metadata with unfinished Web playback/download behaviour.
- Node exposes normalized `/client-api/v1` routes alongside the preserved `/api` and `/media` proxies. See [Upstream API](upstream-api.md) for contracts and [Deployment](deployment.md) for configuration migration.
- Browser downloads still use HEAD preflight and browser handoff. Native task progress, file saving, and directory selection are implemented behind the native download port. Regular startup selection and window-close confirmation remain Task 7.

## Native Programme Commands

Rust owns `list_programmes(requestId)`, `list_programme_dates(programmeId, requestId)`, `list_programme_contents(programmeId, dateId, requestId)`, and `cancel_request(requestId)`. Commands accept string domain IDs and version-4 UUID request IDs. The application manifest and `programme-api` permission restrict them to the local `main` window. The frontend has no general HTTP, filesystem, or Store command permission.

The programme client fixes production access to `https://gw.scgchc.com`, rejects redirects, and uses the existing anonymous guest headers for metadata only. Each operation has a 20-second response-header deadline and a 30-second idle-read deadline. Rust normalizes upstream values into the same DTOs as Node; `videoStandard` maps to `smoothVideo`. The TypeScript adapter validates command results, bridges `AbortSignal`, removes listeners after terminal results, and rejects cancelled requests even if IPC resolves late. Existing `LatestRequest` guards remain in the shared archive flow.

Before exposing services, startup loads a private `desktop.json` using the [official Tauri Store plugin](https://v2.tauri.app/plugin/store/), validates or creates `installationId`, and explicitly saves it. Concurrent requests then share the immutable identity. This value is separate from future shared preferences. Read/write failures surface as `storage` command errors without using an ephemeral identity or terminating the shell. Invalid UUID fields are repaired while unrelated values are retained; unreadable/corrupt files are preserved and reported. Failed stores are unregistered so the plugin cannot overwrite them during its exit-time save.

Cancellation drops pending native HTTP/body futures. Cancellation that precedes registration is retained for at most 60 seconds, with a maximum of 1,024 unique markers. Registration consumes its marker; dropping or completing a request releases its active entry. No production command accepts a test origin or timeout override.

## Native Media Transport Candidate

`src-tauri/src/media/` implements a Rust-owned, media-only HTTP service. It binds `127.0.0.1` on an OS-assigned port. Rust registers validated sources under unpredictable session tokens; HTTP callers cannot supply an upstream URL. Default production policy allows only HTTPS MP4 files on `fscgc.scgchc.com`, with no credentials or nondefault port. Redirects are rejected. Media requests insert only the media Referer and forward Range/If-Range; guest headers, cookies, and authorization are not forwarded.

The service handles GET, HEAD, and OPTIONS, validates Host and any supplied Origin, and preserves media response headers including 206/416 ranges. Headers have a 20-second deadline; upstream reads have a 30-second idle deadline with no whole-video timeout. A capacity-one channel applies backpressure. Its producer owns the upstream response independently of downstream body polling, so session cancellation releases upstream work even when the player stops reading. Shutdown cancels sessions and terminates all owned HTTP connections, including stalled clients.

The current Tauri custom-protocol API accepts a complete response body rather than a cancellable response stream, so this is the fallback candidate from the design. A disposable macOS bundled probe passed playback, seeking, source switching, and close/reopen checks. Windows WebView2, complete process-memory measurement, and final transport acceptance remain pending. Playback commands, domain-source resolution, the Tauri playback adapter, production CSP changes, and shared player integration have not been added. Frontend assets continue to use Tauri's normal bundled-asset protocol.

## Native Downloads

Rust exposes `start_downloads(request)`, `list_downloads()`, `subscribe_downloads(onEvent)`, `unsubscribe_downloads(subscriptionId)`, `cancel_download(taskId)`, `get_download_directory()`, and `choose_download_directory()`. The `download-api` permission grants these commands only to the local main window. Direct frontend Dialog, Store, and filesystem commands remain unavailable. Requests contain programme/date/content IDs and quality; Rust fetches the matching records, validates media policy, applies quality fallback, and derives filenames. Failures remain independent per content item.

The manager reuses Tokio's bounded `mpsc`, `Semaphore(2)`, and tokio-util's `CancellationToken`/`TaskTracker`. Default admission allows at most 102 unfinished tasks, including tasks waiting outside the channel for a concurrency permit. Excess files receive individual queue-full failures. Repeated active content/actual-quality/directory submissions reuse the existing task ID. Cancelling queued work does not wait for running downloads to finish. HTTP uses the fixed media policy, no redirects or guest headers, a 20-second header deadline, and a 30-second idle deadline. Progress events are limited to one every 100 ms per task; state/terminal updates are immediate. Unknown totals stay `null`.

The [official Dialog plugin](https://v2.tauri.app/plugin/dialog/) selects a directory in Rust when none is saved. Cancelling creates no tasks. Selection is serialized and the directory is saved privately in `desktop.json`; a removed or inaccessible saved location fails explicitly. Failed saves restore the previous in-memory directory and report a storage error. The manager validates the directory again when starting work.

Each destination directory has a small `.sctv-dl.lock` ownership marker, retained after exit. An OS file lock prevents another desktop instance from recovering active artifacts there. Tasks reserve case-insensitive unique names and write UUID-specific `.part` files, with matching versioned `.json` recovery records. File names handle Windows devices/invalid characters and Unicode truncation; overly long directory paths fail with a request to choose a shorter location. Flush, sync, and writer closure precede no-clobber finalization. A retained file identity handle protects live reservations from publishing or deleting a replacement at the temporary path; queued jobs retain only that handle. Existing files retain their bytes, including when a competing destination appears during transfer. Cancellation/failure removes owned temporary files and reservations; cleanup failures surface in task errors. A handled replacement is preserved and its owned journal removed so the next open cannot recover it. Initialization-write failures remove newly owned lock/journal files and report cleanup failures. After a process interruption, recovery treats an exact versioned UUID record plus its matching regular temporary path as an owned pair; it has no live file identity handle. Unknown files and records remain untouched.

The TypeScript adapter validates command/channel payloads. The shared download store subscribes before requesting its snapshot and merges monotonic revisions, preserving terminal events that arrive during hydration. Its desktop-only task drawer remains in the application shell across page navigation, shows received bytes/unknown totals, and offers cancel/retry. Retry uses the content reference and actual quality. Preparation failures remain visible in the drawer. The drawer loads lazily, so Web startup does not load its UI chunk.

Task history is limited to the current process; no restart resume is implemented. Application exit stops admission and awaits blocking directory preparation, transfer cancellation, and file cleanup before releasing directory locks. User confirmation on window close, pending-picker exit coordination, preference hydration, and complete native platform composition remain Task 7. Installed Windows behaviour is still unverified; the macOS probe and automated evidence are recorded below.

The [implementation plan](superpowers/plans/2026-10-16-tauri-desktop.md) tracks phase status. [Media validation](desktop-media-validation.md) records what was actually checked and what remains open.
