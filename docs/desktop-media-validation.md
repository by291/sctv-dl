# Desktop and Media Validation

The sections below are historical phase evidence. Current history, cache, and durable-download acceptance is recorded in [Web and Desktop Feature Validation](web-desktop-feature-validation.md); older process-only and cancel-on-exit observations describe those earlier builds.

This record distinguishes the native shell, Web media compatibility, native transport experiments, and the pending two-platform acceptance gate.

## Environment

Validated on 2026-10-16 with macOS 27.0.1, arm64, Rust/Cargo 1.98.0, Node 26.11.1, pnpm 12.9.1, Tauri CLI 2.12.3, and Tauri core 2.12.4. Xcode was available. The proposed macOS 13 minimum, Windows compilation, and Windows WebView2 runtime were not tested.

## Native Shell

- Built the release Rust executable and an ad-hoc-signed `.app` with bundled frontend assets.
- Launched the bundle through native application automation. The accessible document URL was `tauri://localhost/`; navigation, programme-library controls, and the expected API-unavailable state rendered without a running project Node server.
- This proves native shell startup and bundled asset loading. It does not prove native programme access, video playback, downloads, routing reloads, or public distribution readiness.
- Closed the temporary native application after checking it.

## Web Integration and Upstream Media

The normalized catalogue returned 40 real programmes. Checked programme details at desktop width (1280 × 900) and narrow width (390 × 844), dark/system and light themes, settings navigation, focused empty search feedback, and restored the temporary system-theme preference. Automated regressions cover browser handoff, partial batch failure, quality fallback, stale responses, and player teardown.

For programme `1`, the latest tested date was `2026-10-15`. Its archive contained 14 records. Download preparation returned one file with a backend-derived filename; playback preparation returned two distinct variants.

Through the existing Web media proxy:

| Probe                 | Observed result                    |
| --------------------- | ---------------------------------- |
| HEAD                  | HTTP 200, `video/mp4`              |
| `Range: bytes=0-1023` | HTTP 206                           |
| Content-Range         | `bytes 0-1023/563536485`           |
| Body consumed         | 1,024 bytes, then reader cancelled |

No full episode was downloaded for this verification. These observations apply to the tested upstream object and date, not every video or native WebView.

## Native Metadata Phase

A temporary release bundle used the real Rust command handlers and `programme-api.tauri.ts`, with normal Tauri bundled assets and a separate test application identifier. With project Node servers stopped, the macOS native document at `tauri://localhost` reported 40 programmes, 3,394 dates for programme `1`, and 14 contents for its latest tested date (`2026-10-15`). Adapter cancellation, cancellation before registration, and native invalid-ID rejection all passed. The probe was closed and its temporary source, bundle, and application data were removed.

Automated native tests cover delayed headers/bodies, idle timeout versus progressing bodies, cancellation cleanup, bounded/expiring early cancellation, shared normalization fixtures, identity persistence/errors (including preservation of corrupt files through application exit), and IPC command routing. ACL tests reject secondary windows, remote origins, and direct frontend Store access. The native adapter is also exercised through the existing archive composable with out-of-order programme replies. Deterministically slow upstream responses were tested against Rust HTTP stubs; the native window probe used live upstream data and immediate cancellation. Windows interactive coverage remains pending.

Final metadata-phase checks passed 215 TypeScript tests and 18 native integration tests, including raw floating-point JSON at the safe-integer boundary and cross-language BOM/NEL URL fixtures. Read failures, successful persistence, and corrupt-file preservation through exit are covered. Dedicated Store save-failure injection was subsequently added in the download phase below.

This phase verifies the native metadata service and bridge. Regular application startup still composes Web adapters; it does not establish complete native browsing/playback/download integration or settle the media transport gate.

## Native Media HTTP Candidate

### Transport Investigation

The installed Tauri 2.12.4 `UriSchemeResponder` accepts one complete `Response<Cow<'static, [u8]>>`; it does not provide a streaming response body or a request-stop callback. Wry 0.57.0's WKWebView handler removes stopped tasks internally without notifying that responder. The [official streaming example](https://github.com/tauri-apps/tauri/blob/dev/examples/streaming/main.rs) also reads the complete file for a no-Range request. This interface cannot satisfy the design's full no-Range streaming and early-disconnect requirements with a small response buffer. It was rejected before writing a second custom-protocol implementation.

The fallback candidate uses Rust/Tokio, Axum routing, and explicitly owned Hyper HTTP/1 connections. It serves media only from a random `127.0.0.1` port, under opaque session URLs. Frontend assets remain on Tauri's normal bundled-asset protocol. No production startup listener, playback command, adapter, or player integration is enabled yet.

### Automated Evidence

Twelve native media tests use disposable local upstreams and cover:

- Shared source-policy fixtures, session validation, token isolation, exact Host checks, allowed/denied Origin handling, supported methods, and closed-session rejection.
- HEAD, full no-Range GET, bounded/open-ended/suffix ranges, 206/416 headers, concurrent ranges, and unknown response lengths.
- Media Referer insertion, metadata/cookie/authorization isolation, redirect rejection, and unexpected content-type rejection.
- Separate header/idle deadlines, slowly progressing bodies without a whole-file timeout, cancellation during headers, downstream disconnect, and active session closure.
- Backpressure against a generated 1 GiB stream: a paused reader must not prefetch 128 MiB. This catches whole-file buffering. The HTTP service streams incrementally rather than assembling a protocol response; the custom protocol's 1 MiB per-response budget is not a total-process memory bound.
- A raw TCP client that never reads: closing the session releases the upstream body, and server shutdown returns instead of waiting indefinitely for that client.

The final review identified that a purely pull-driven body would stop observing cancellation under downstream backpressure. Both raw-TCP regressions failed before the fix. The producer now observes cancellation independently of body polling through a capacity-one channel, and the server owns and terminates its connections on shutdown. Both regressions passed after the fix.

### macOS WKWebView Evidence

A disposable, ad-hoc-signed release bundle loaded test assets at `tauri://localhost`, with project Node servers stopped. It ran the real media service against a local synthetic H.264 fixture: 60 seconds, 320 × 180, 15 fps, about 8.6 MiB of video padded with a valid sparse MP4 `free` box to a 1 GiB resource. Both variant URLs served that same clip; this tests source switching and position retention rather than visual quality differences. The engine was the system WKWebView on macOS 27.0.1 arm64; a separate WebKit build number was not captured.

| Action                  | Observed result                                                  |
| ----------------------- | ---------------------------------------------------------------- |
| Initial load/play       | 60-second metadata, native playing state, no media error         |
| Forward seek            | Seek completed at 35.00 seconds                                  |
| Backward seek           | Seek completed at 5.00 seconds                                   |
| Switch to smooth source | New source loaded, retained 9.30 seconds, then continued playing |
| Close                   | Player paused/source cleared; upstream active count reached zero |
| Reopen/play             | A fresh session token loaded and played successfully             |
| Upstream header audit   | Zero invalid-header requests                                     |

The Rust process RSS was 114,176 KiB during playback and 114,736 KiB after seeking, switching, and reopening, an increase of 560 KiB. The fixture server sent 110,231,558 bytes across ten requests in that probe, rather than reading the complete 1 GiB object. These are two samples of the Rust process, not total application memory; WKWebView WebContent memory was not attributed. Complete memory acceptance remains open. After the backpressure fix, a fresh bundle again passed play, close with zero active upstreams, reopen with a new token, and play. The temporary app was quit; its harness and fixture were removed, and the normal bundle was rebuilt.

A separate disposable Rust probe used live programme `1`, date `2026-10-15`, through the candidate service with its default CDN policy:

| Probe                 | Observed result          |
| --------------------- | ------------------------ |
| HEAD                  | HTTP 200, `video/mp4`    |
| `Range: bytes=0-1023` | HTTP 206                 |
| Content-Range         | `bytes 0-1023/563536485` |
| Body consumed         | 1,024 bytes              |

No complete episode was downloaded. This checks the candidate's real upstream access, not live interactive playback in both WebViews.

## Transport Acceptance Boundary

The custom-protocol interface has been ruled out; media-only HTTP is selected and integrated. Windows WebView2 and complete memory evidence remain release acceptance requirements. The revised [design](superpowers/specs/2026-10-16-tauri-desktop-design.md) separates that acceptance from completing application integration. Repeat native seeking, source switching, cleanup, and memory checks on Windows and the final installed application. The proposed minimum OS versions and Windows compilation/runtime remain unverified.

## Native Download Phase

The Rust manager, domain commands, directory persistence/selection, validated Channel adapter, shared task store, and desktop-only task drawer are implemented. At this earlier probe, startup still composed Web adapters. The integrated-application section below supersedes that boundary.

Automated cases cover two-concurrent execution, bounded admission including semaphore waiters, active-job deduplication, queued/running cancellation, slot release after cleanup, progress throttling and exact cancellation byte counts, unknown totals, truncated bodies, MIME/redirect rejection, stale references, fallback, and independent per-file failures. File cases cover portable names/Unicode boundaries, Windows superscript device names, long paths, case-only and concurrent collisions, competing destinations, flush/finalization/cleanup failures, replaced directories and ordinary files at temporary paths, partial lock/journal writes with directory reuse, shutdown/delayed preparation, macOS normalized dangling symlinks, and recognized leftover recovery. Command tests download exact stub bytes through the real domain IPC entry point and reject secondary windows, remote origins, and direct Dialog/Store/filesystem calls. Deterministic Store serializers now cover identity save failure and failed-directory-save rollback. Frontend cases cover subscription-before-snapshot, stale/terminal revisions, late-subscription disposal, retry arguments, and task-panel actions.

A disposable macOS release bundle used the real commands, Channel adapter, task store, and drawer, with an isolated Store file and local synthetic HTTP fixtures. Its first native folder picker was cancelled: the command returned `kind: cancelled` and the drawer remained empty. A second selection chose a dedicated test directory. The batch then showed standard-quality fallback, active progress with unknown total, one MIME failure, one missing-content preparation failure retained in the drawer, and completed files. A running task was cancelled at 448 KiB; retry created a new task and reused the released filename safely. The final four files (two 48 KiB and two 640 KiB fixtures, including collision suffixes) matched their generated byte patterns exactly. No `.part` or recovery `.json` remained in the destination after exit. These are synthetic download fixtures, not real episode downloads or playback tests.

The same drawer was checked through a disposable browser fixture at 1280 × 900 in light theme and 390 × 844 in dark theme, including known/unknown totals, failure feedback, completed state, loading, empty list, connection error/reconnect affordance, keyboard Escape, and trigger-focus restoration. This browser fixture validates presentation; the separate native bundle validates the Rust/IPC/file path. The temporary browser tab, viewport override, server, native app, source harness, and fixtures were cleaned up, and the normal application entry point restored.

Windows interactive downloads, minimum macOS coverage, settings restart tests, and final complete-application acceptance remain pending. Native file policy tests on macOS are not a substitute for Windows runtime checks.

## Settings and Exit Foundation

Task 7 is partial. Rust preference commands/private storage, the validated adapter, shared hydration/save ordering, native directory settings UI, close/menu confirmation, and standard menus are implemented. Complete native platform selection and frontend queued-save acknowledgement before exit remain pending the playback/composition phase.

A disposable macOS release bundle used real settings/download commands, production stores/views, an isolated Store, and a local synthetic never-ending MP4 body. Explicitly flushed theme, quality, and favourite changes reappeared after restart; the selected directory and installation UUID stayed stable. Restart showed an empty task list. Cmd-Q and titlebar close displayed one main-window confirmation while a task was active. Rejecting kept the task alive; a repeated quit request added no prompt; accepting exited the process and left only the directory lock marker, with no temporary files or journals. The native menu initially bypassed confirmation through the predefined Quit action; source inspection and an installed-probe regression verified the replacement menu. Parented confirmation was also checked after observing the unparented plugin message using a separate system notification. Pending-operation coordination is covered by Rust regressions; system Dock Quit confirmation is still unavailable through the current framework hook.

The actual Web app retained theme/quality through reload and returned the live 40-programme catalogue. Settings presentation was checked at 1280 × 900 and 390 × 844, in light/dark themes, with long directory paths, persistence/directory errors, recovery, and keyboard traversal. Deferred-response component regressions verify that initial directory success/failure cannot overwrite a newer choice, and that cancellation retains an unresolved error. The shared store tests cover late hydration, serialized writes, older save notifications, subscription updates during load, write-failure warnings, and listener disposal.

This is an isolated settings/exit probe, not full installed-client acceptance. At this earlier probe, Windows, minimum macOS, native playback, and complete startup were unverified. No full live episode was downloaded in that probe. Temporary processes, browser overrides, probe sources, fixtures, and isolated Store were removed; the normal entry point and application bundle were restored.

## Integrated Desktop Application — 2026-10-16

The normal release application (15.61 MiB, ad-hoc signed) was launched on macOS 27.0.1 arm64 with no project service listening on ports 5180/4173. Its `tauri://localhost#/` entry selected the full native platform, loaded 40 programmes, 3,394 dates, and 14 latest-date contents for programme `1`. No temporary playback frontend or alternative Rust main was used.

- A real 17-second clip played through the Rust session endpoint. Seeking to 00:04 and switching from standard to smooth retained 00:04 after metadata loaded. Closing with Escape released the shared preview. Both sources were opaque loopback URLs; frontend assets remained on Tauri's asset protocol.
- The native picker selected a disposable path containing Chinese text and a space. A smooth clip reached `completed` in the task drawer and produced a 1,928,060-byte MP4 with an `ftyp` header. No `.part`/journal files remained.
- Selecting smooth/dark and immediately pressing Cmd-Q persisted both values; restart retained them, the directory, and a later favourite. Restart showed an empty task history. The private installation identity was preserved.
- Closing with an active full-episode task showed a parented confirmation; rejection returned to the running app. That task finished while other checks ran, producing 563,536,485 bytes; the disposable episode was removed afterward. A second task followed by immediate Cmd-Q showed confirmation, and acceptance ended the process with no `.part`/journal leftovers.
- The macOS termination bridge compiles and its missing-method/duplicate-install regression passes. Interactive Dock inspection timed out in UI automation, so Dock acceptance remains unverified. Window close and Cmd-Q are independently verified.
- The shared Web app retained browser-managed directory text and no native task actions. Desktop and 390x844 layouts, preview opening/Escape, light/dark/system selection, and normal Web routing were checked. The narrow page had equal viewport/document width (390 px). The final native window was resized to approximately 392 by 542 logical pixels with usable navigation, task action, and library layout, then restored and closed.

The complete Rust suite passes 67 tests, including four unit tests, with strict Clippy and formatting. Shared checks pass 247 tests in 45 files after review, including release-version, source-tag identity, and required-credential guards. A disposable Git fixture reproduces a same-named branch shadowing the release tag; the guard rejects a mismatched checkout or missing tag and resolves only the tag commit. CI workflows are prepared for Windows x64 and native arm64 macOS runners; both pass official Actionlint validation but were not dispatched. Test-origin browser preferences/viewport and native preference/directory keys were restored, the temporary Web server was stopped, and the final normal app smoke-test instance was closed. Local build/test evidence does not establish Windows, minimum macOS, MSRV 1.90, complete WebContent/process-memory attribution, signing/notarization, or public release acceptance.
