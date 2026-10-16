# Desktop and Media Validation

This record distinguishes the native shell, Web media compatibility, and the pending native playback transport decision.

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

## Pending Native Transport Gate

No production media transport has been selected. The disposable custom-protocol/streaming investigation, bounded-memory measurement, native seek/quality/close-reopen checks, and Windows comparison remain pending. The Web HEAD/Range probes above do not replace those checks.

Before Task 5, apply the decision rule in the [design](superpowers/specs/2026-10-16-tauri-desktop-design.md): retain an asynchronous custom protocol only if the required request shapes and lifecycle work on both target WebViews with bounded memory; otherwise validate the media-only Rust loopback fallback. Keep frontend assets on Tauri's normal bundled-asset protocol.
