# Desktop and Media Validation

This record distinguishes the native shell, Web media compatibility, native transport experiments, and the pending two-platform acceptance gate.

## Environment

Validated on 2026-10-16 with macOS 27.0.1, arm64, Rust/Cargo 1.98.0, Node 26.11.1, pnpm 12.9.1, Tauri CLI 2.12.3, and Tauri core 2.12.4. Xcode was available. The proposed macOS 13 minimum, Intel architecture, Windows compilation, and Windows WebView2 runtime were not tested.

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

Final checks passed 215 TypeScript tests and 18 native integration tests, including raw floating-point JSON at the safe-integer boundary and cross-language BOM/NEL URL fixtures. A dedicated Store save-failure injection test remains deferred to the settings phase; read failures, successful persistence, and corrupt-file preservation through exit are covered.

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

## Remaining Native Transport Gate

The custom-protocol interface has been ruled out for this design; media-only HTTP remains a candidate pending Windows WebView2 and complete memory evidence. No production transport acceptance is claimed. Follow the decision rule in the [design](superpowers/specs/2026-10-16-tauri-desktop-design.md) before completing playback integration. Repeat native seeking, source switching, cleanup, and memory checks on Windows and the final installed application. The proposed minimum OS versions, Intel macOS, and Windows compilation/runtime remain unverified.
