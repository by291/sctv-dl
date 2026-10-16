# Desktop Development

The repository contains a Tauri 2 shell, shared contracts/Web adapters, native programme services with a TypeScript adapter, and a Rust media transport candidate. The normal application still starts with Web adapters; full native composition, playback integration, downloads, and preference hydration remain later phases. It is not a complete desktop client.

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

Native tests cover programme normalization/HTTP, cancellation, command permissions, installation-identity persistence, and media streaming/lifecycle. HTTP tests use disposable local Axum stubs. Axum and Hyper are runtime dependencies for the media-only HTTP candidate described below; no listener starts in the regular application yet. Native build products and generated schemas are ignored. Application icons are generated from `public/favicon.svg` with `pnpm tauri icon public/favicon.svg`; keep only the desktop icon outputs when regenerating them.

## Current Integration Boundary

- `shared/contracts/` contains application DTO schemas and inferred types shared by browser and Node. `shared/fixtures/` contains normalization examples consumed by both Node and Rust tests.
- `src/shared/platform/` defines injectable programme, playback, download, and settings ports. Components consume ports; native API imports in Vue components are rejected by ESLint.
- `src/platform/web-platform.ts` composes the current Web adapters. The native programme adapter exists in `programme-api.tauri.ts`, but environment selection remains Task 7 so regular startup cannot mix native metadata with unfinished Web playback/download behaviour.
- Node exposes normalized `/client-api/v1` routes alongside the preserved `/api` and `/media` proxies. See [Upstream API](upstream-api.md) for contracts and [Deployment](deployment.md) for configuration migration.
- Browser downloads still use HEAD preflight and browser handoff. Native task progress, files, directory selection, and exit confirmation remain future work.

## Native Programme Commands

Rust owns `list_programmes(requestId)`, `list_programme_dates(programmeId, requestId)`, `list_programme_contents(programmeId, dateId, requestId)`, and `cancel_request(requestId)`. Commands accept string domain IDs and version-4 UUID request IDs. The application manifest and `programme-api` permission restrict them to the local `main` window. The frontend has no general HTTP, filesystem, or Store command permission.

The programme client fixes production access to `https://gw.scgchc.com`, rejects redirects, and uses the existing anonymous guest headers for metadata only. Each operation has a 20-second response-header deadline and a 30-second idle-read deadline. Rust normalizes upstream values into the same DTOs as Node; `videoStandard` maps to `smoothVideo`. The TypeScript adapter validates command results, bridges `AbortSignal`, removes listeners after terminal results, and rejects cancelled requests even if IPC resolves late. Existing `LatestRequest` guards remain in the shared archive flow.

Before exposing services, startup loads a private `desktop.json` using the [official Tauri Store plugin](https://v2.tauri.app/plugin/store/), validates or creates `installationId`, and explicitly saves it. Concurrent requests then share the immutable identity. This value is separate from future shared preferences. Read/write failures surface as `storage` command errors without using an ephemeral identity or terminating the shell. Invalid UUID fields are repaired while unrelated values are retained; unreadable/corrupt files are preserved and reported. Failed stores are unregistered so the plugin cannot overwrite them during its exit-time save.

Cancellation drops pending native HTTP/body futures. Cancellation that precedes registration is retained for at most 60 seconds, with a maximum of 1,024 unique markers. Registration consumes its marker; dropping or completing a request releases its active entry. No production command accepts a test origin or timeout override.

## Native Media Transport Candidate

`src-tauri/src/media/` implements a Rust-owned, media-only HTTP service. It binds `127.0.0.1` on an OS-assigned port. Rust registers validated sources under unpredictable session tokens; HTTP callers cannot supply an upstream URL. Default production policy allows only HTTPS MP4 files on `fscgc.scgchc.com`, with no credentials or nondefault port. Redirects are rejected. Media requests insert only the media Referer and forward Range/If-Range; guest headers, cookies, and authorization are not forwarded.

The service handles GET, HEAD, and OPTIONS, validates Host and any supplied Origin, and preserves media response headers including 206/416 ranges. Headers have a 20-second deadline; upstream reads have a 30-second idle deadline with no whole-video timeout. A capacity-one channel applies backpressure. Its producer owns the upstream response independently of downstream body polling, so session cancellation releases upstream work even when the player stops reading. Shutdown cancels sessions and terminates all owned HTTP connections, including stalled clients.

The current Tauri custom-protocol API accepts a complete response body rather than a cancellable response stream, so this is the fallback candidate from the design. A disposable macOS bundled probe passed playback, seeking, source switching, and close/reopen checks. Windows WebView2, complete process-memory measurement, and final transport acceptance remain pending. Playback commands, domain-source resolution, the Tauri playback adapter, production CSP changes, and shared player integration have not been added. Frontend assets continue to use Tauri's normal bundled-asset protocol.

The [implementation plan](superpowers/plans/2026-10-16-tauri-desktop.md) tracks phase status. [Media validation](desktop-media-validation.md) records what was actually checked and what remains open.
