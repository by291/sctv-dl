# Flutter Agent Instructions

These instructions apply to this Flutter application, including its native hosts. Root Android sources belong to a separate Kotlin client.

- Preserve the approved specification and plan under ../docs/superpowers/. Use English documentation, comments and test names, with Chinese product copy.
- Organize by domain/data/platform/features/app/design ownership. Features consume pure domain contracts, never sibling features or concrete data/platform adapters.
- Keep platform handles and effects with their lifecycle owner. Cancellation and stale-result rejection are separate safeguards. Player disposal waits for committed route exit, and PiP retains ownership.
- Validate unknown upstream data before constructing domain models. Keep IDs as decimal strings and preserve the shared quality, date, URL and filename contracts.
- Run dart format, flutter analyze --fatal-infos, and flutter test. Add meaningful regression coverage for behaviour; exercise native plugins on disposable runtimes before claiming native correctness.
- Never embed SDK paths, credentials, generated caches, or signing material in portable source. Keep the application lockfile tracked.
- Existing unrelated Kotlin/Web/Tauri changes must remain untouched. Do not commit implementation unless requested.
