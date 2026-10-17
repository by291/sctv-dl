# Pinned playback adapter repairs

Source: `better_player_plus` 2.0.0, downloaded by `flutter pub get` from
[pub.dev](https://pub.dev/packages/better_player_plus/versions/2.0.0).
The upstream source license remains in `LICENSE`; the application selects this
portable copy through its dependency override. No shared pub cache is modified.

The unused upstream example, tests, contributor instructions and development-only
analysis configuration are omitted from this runtime adapter copy.

Application-specific repairs:

- Kotlin bytecode explicitly targets JVM17 even when Flutter selects a newer JDK
  under AGP9 compatibility mode.
- The public aspect-ratio configuration enum is exported, allowing the adapter
  to select uncropped iOS rendering without importing private package files.
- Android uses Media3's maintained `OkHttpDataSource` with both HTTP and HTTPS
  redirects disabled, bounded connect/read deadlines and streaming Range reads.
  Upstream `DefaultHttpDataSource` followed same-protocol redirects even when
  cross-protocol redirects were disabled.
- Android prefetch stops at 30 seconds or a 24 MiB Media3 sample-buffer target,
  with byte thresholds taking priority even below the minimum buffer duration.
  Upstream allowed 109 minutes and Media3 chose about 138 MiB for video+audio;
  adding decoder, Flutter and HTTP/2 buffers exhausted a 192 MiB Java heap on a
  full programme. This is a loading threshold, not a whole-process memory cap:
  a sample/loader iteration and transport/decoder buffers need separate headroom.
  Native allocator regression covers stop, start and resume at the byte limit.
- iOS network MP4 uses an `AVAssetResourceLoader` with a non-caching URLSession.
  Redirect delegate rejects redirects, responses stream directly into AVPlayer's
  loading request, each Range request is capped at one MiB, and cancelled
  AVPlayer requests cancel their network task. There is no whole-video buffer,
  arbitrary URL relay, or application transfer queue. Local files use AVPlayer
  normally. HLS/DASH/DRM are outside the application's MP4 contract.
- Automatic inline iOS PiP is disabled; only the explicit application action may
  retain playback on background entry.
- Android reports native play intent instead of treating buffering as pause.
  Both platforms pause on audio interruption/route loss without automatic resume.
  The audio-mixing setter returns its native future so session setup can await
  exclusive audio ownership and report failure.
- Native first-frame readiness is separate from metadata initialization. Android
  forwards Media3 `onRenderedFirstFrame`; iOS observes the active AVPlayerLayer's
  `isReadyForDisplay` and releases the observation on disposal. The Dart value
  preserves readiness through pause/buffering and resets it for a new source.
  The application keeps its poster until native output and route entry are ready.
- Source preparation accepts an initial position, including quality changes.
  Android passes it to Media3 before preparing the source, so the first rendered
  frame belongs to the resume point. iOS keeps the AVPlayerLayer disconnected
  until the exact initial seek finishes, then waits for display readiness.
  Superseded seeks and disposed/replaced items cannot reveal stale output.
  Ordinary seeking and predictive-back cancellation do not reset readiness.
- Video controller disposal shares one completion future so delayed route
  cleanup can await native resource release without releasing it twice.
- Seeking from an ended paused position preserves play intent. Disposal also
  completes pending initialization, so a cancelled source switch cannot hang.
- Android `content://` local media retains its URI instead of being prefixed
  with `file://`, and extensionless MediaStore IDs select progressive MP4
  parsing without indexing a nonexistent filename extension.

Existing call sites remain source-compatible; the pinned version stays 2.0.0. Rebase these small patches when
upgrading; do not replace them with a preflight-only redirect check. JVM fixture
checks cover redirect rejection and streaming response closure; native decoding,
PiP, audio interruption and iOS resource-loader behavior require device evidence.
