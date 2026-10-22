# Apple Client Instructions

These instructions supplement the repository instructions for `apple/`.

- Keep deployment targets at iOS/iPadOS 26 and macOS 26. Use Swift 6 concurrency checking.
- Application roots compose dependencies. Core values and policies do not import SwiftUI, AVKit or database libraries. Features consume core protocols rather than constructing native services.
- Keep each file focused on one responsibility. Group dependencies, state, derived values, actions and lifecycle methods with logical blank lines. Inside actions, separate validation, computation, external calls and state commits.
- Use enums with associated values for mutually exclusive states. Comments explain ownership, cancellation versus stale-result rejection, transaction boundaries and platform restrictions.
- Keep all player/transfer/file resources with a visible lifecycle owner. Revalidate session, attempt and revision identities after suspension points. An actor does not make a multi-step asynchronous workflow atomic.
- Write comments, documentation, tests and commit subjects in English. Preserve Chinese product copy and programme names.
- Do not use unsupported AVURLAsset header options. Media requests follow the shared HTTPS host policy and carry media headers only.
- Use the checker documented in [README](README.md). Distinguish compilation, package tests, simulator checks, minimum-OS checks and physical-device acceptance.
- Use disposable simulators and fixture media; do not alter existing devices or download complete upstream episodes for verification.
- Keep build output, recordings, generated test fixtures and local signing settings out of Git. Commit and push only when requested.
