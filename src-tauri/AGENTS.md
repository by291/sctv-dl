# Native Desktop Instructions

These instructions apply to `src-tauri/` in addition to the root [AGENTS.md](../AGENTS.md). Native integration and operating contracts are described in [Desktop Development](../docs/desktop.md).

## Responsibilities

- Keep `lib.rs` as application composition and `commands/` as Tauri parameter, State, Channel, and result adapters. Application workflows belong to the concrete services they coordinate.
- Programme modules own upstream normalization, broadcast references, and video selection rules. Media owns opaque playback sessions and streaming transport. Downloads own admission, task state, transfer, and file reservations. Settings own their Store and synchronization details. Lifecycle owns coordinated exit.
- Preserve IPC command names, argument names, serialized DTOs, error codes, and existing settings keys. Production commands must not accept arbitrary URLs, origins, filesystem paths, or timeout overrides.
- Reuse Tokio, tokio-util, Reqwest, Hyper/Axum, Serde, and official Tauri plugins. Introduce an abstraction only when it clarifies an existing responsibility.

## Rust Readability

- Use rustfmt for mechanical formatting, then manually review each owned function and macro for logical paragraphs; rustfmt alone does not establish readability. Separate imports, types, impl blocks, and adjacent methods with clear blank lines. Within a function, separate validation, resource acquisition, external work, state commitment, and cleanup where those phases change. Keep a request/result next to its immediate stale or cancellation guard. Expand packed `select!` branches and nested JSON fixtures when their control flow or fields become hard to scan; do not insert blank lines after every statement.
- Keep each function at one main level of abstraction. Extract named workflow steps or pure rules; split modules by independent responsibilities rather than line count.
- Make lock scopes visible with local blocks. Copy the data needed for external work, then release shared state locks. Keep filesystem work and potentially blocking lock waits in `spawn_blocking`; move the relevant operation/admission guard into that worker.
- Document the ownership and completion contracts of resource-bearing APIs: who cancels, who awaits, what a successful return guarantees, and how failure cleans up. `Drop` provides best-effort fallback; explicit finalization must report errors.
- Use typed state and error codes where they express a real invariant. Keep useful local inference and avoid wrapping every string or adding traits solely for tests.
- Explain non-obvious platform, protocol, and concurrency constraints. Keep `SAFETY` comments beside unsafe code and preserve the macOS delegate/ABI checks. Do not replace justified `unwrap()` calls mechanically.
- Keep fixtures and assertions readable, including code inside JSON macros. Tests should exercise observable contracts, not source formatting or private function structure.

## Resource Contracts

- Preserve bounded admission, two concurrent transfers, task revision ordering, terminal-state guards, and independent per-file failures.
- Preserve live file identity checks, no-clobber finalization, UTF-8/UTF-16 filename limits, recognized recovery records, and protection of replacement/unknown files. Establish rollback ownership immediately after creation, including failures before the normal reservation exists.
- Preserve separate response-header and idle-read deadlines. Media must retain Range/HEAD/416, strict target/Host/Origin checks, independent producers, and bounded backpressure.
- Every spawned service task needs an owner. Shutdown must stop admission, cancel work, and await the tasks it owns before releasing resources.
- Preserve settings rollback and corrupt-file protection. Exit must drain frontend saves, freeze admission, wait for existing operations, confirm when required, and await cleanup. Rejecting exit must restore normal operation.
- Retain internal error causes while keeping the `{code, message}` IPC response stable. Report failures once at their owning boundary; omit expected cancellation and avoid logging full media URLs, query values, or guest identity headers.

## Verification

Run focused Rust tests while changing a workflow, then run `pnpm desktop:check` from the repository root. It checks rustfmt, Clippy with warnings denied, and the complete Rust test suite. Run `pnpm check` and `pnpm build` when browser adapters, shared contracts, build configuration, or cross-platform integration changes.

Use disposable directories and local upstream stubs. Cover rollback, cancellation, shutdown completion, lock/I/O races, and serialized compatibility when those contracts change. Keep automated checks separate from installed-app, OS-dialog, WebView, Windows, signing, and release validation.
