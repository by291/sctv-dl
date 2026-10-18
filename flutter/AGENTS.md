# Flutter Agent Instructions

These instructions apply to this Flutter application, including its native hosts. Root Android sources belong to a separate Kotlin client.

- Preserve the approved specification and plan under ../docs/superpowers/. Use English documentation, comments and test names, with Chinese product copy.
- Organize by domain/data/platform/features/app/design ownership. Features consume pure domain contracts, never sibling features or concrete data/platform adapters.
- Keep platform handles and effects with their lifecycle owner. Cancellation and stale-result rejection are separate safeguards. Player disposal waits for committed route exit, and PiP retains ownership.
- Validate unknown upstream data before constructing domain models. Keep IDs as decimal strings and preserve the shared quality, date, URL and filename contracts.
- Run dart format, flutter analyze --fatal-infos, and flutter test. Add meaningful regression coverage for behaviour; exercise native plugins on disposable runtimes before claiming native correctness.
- Never embed SDK paths, credentials, generated caches, or signing material in portable source. Keep the application lockfile tracked.
- Existing unrelated Kotlin/Web/Tauri changes must remain untouched. Do not commit implementation unless requested.

## Responsibilities and readability

- Give each file one coherent responsibility. Extract separately changing rules and workflows, not arbitrary line counts. Keep a function at one main abstraction level.
- Separate imports, contracts, state, derived values, actions and lifecycle methods with meaningful blank lines. Inside workflows, separate validation, external calls and state changes. Keep related state/actions together when a class owns several concerns.
- Separate constructors from fields and keep methods visibly distinct, including their annotations and documentation. Group dependencies, request/lifecycle bookkeeping and presentation state by concern. Keep short related field declarations together.
- Within a function, use paragraphs for validation, preparation, external work, result interpretation and state commitment. Keep an awaited operation with its immediate cancellation/stale-result check. Separate widget-local calculations from the returned widget tree without spacing every widget argument or statement.
- `dart format` handles syntax layout; it does not choose semantic paragraphs. Review logical grouping manually after extraction and formatting, and add comments only where a constraint needs explanation.
- Name state by its role: confirmed values, pending intent, observation generations, task attempts and durable revisions are different concepts. Expose read-only collections and explicit restoration actions instead of externally writable controller fields.
- Explain why ordering, cancellation, stale-result guards or cleanup ownership is necessary. Avoid assignment narration and comment quotas. Use Dart documentation comments for reusable contracts and ownership constraints.
- Keep programme loading, favourite persistence, settings persistence and native operation errors at their owning boundaries. Retrying a failed desired value must not blindly toggle it again.
- Keep native file effects outside the download transition lane. Claims protect the same task; attempt/revision guards protect final commits. Durable public locations precede private-source cleanup. Observation must remain available while effects run.
- Keep route registration, route adapters, navigation actions, input restoration and concrete bootstrap separate. Bootstrap rollback and shutdown attempt every independent cleanup step and preserve primary failures.
- Own timers, subscriptions, native handles and asynchronous errors explicitly. Rejected serialized operations must not poison later work; repeated disposal returns the same completion. Use `unawaited` only where the owning boundary handles errors or the called operation already does so.
- Pages compose focused presentation components; controllers own selection and state transitions. Never mutate selection during `build`. Preserve widget identity, scroll anchors, cover transitions and accessibility during extraction.
- The Android activity and iOS delegate register capabilities; file-channel and player-environment owners implement them. Keep method names/payloads compatible. Do not mechanically reformat vendored plugins.

## Quality gates

From this directory, run `dart format --output=none --set-exit-if-changed lib test test_driver integration_test tool`, `dart run tool/check_boundaries.dart`, `flutter analyze --fatal-infos` and `flutter test`. The structural checker reads Dart directives, including conditional imports and exports; domain remains pure, features cannot import siblings, and concrete composition belongs in app. Its tests use temporary directories.

Use controlled futures for concurrency regressions and observable behavior for extraction checks. Native host changes require Android and iOS compilation and focused disposable-runtime checks; report unsupported/manual device acceptance separately. Official references: [Effective Dart](https://dart.dev/effective-dart), [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations), and [Flutter testing](https://docs.flutter.dev/testing/overview).
