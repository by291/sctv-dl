# Apple Client Instructions

These instructions supplement the [repository instructions](../AGENTS.md) for `apple/`. [Apple Architecture](../docs/apple.md) owns module and lifecycle contracts; [README](README.md) owns setup, checks, dependency resolution and verification scope.

## Standards and Scope

Use the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for naming and API semantics. Use the [Google Swift Style Guide](https://google.github.io/swift/) for file organization, logical whitespace and documentation, and [Airbnb's Swift Style Guide](https://swift.airbnb.tech/) for additional SwiftUI and callback organization guidance. These community guides are references, not a single mandatory language standard.

Mechanical formatting belongs to [`.swift-format`](.swift-format) and the formatter commands in [README](README.md). Retain the project's four-space indentation and 100-column configuration; do not copy another guide's conflicting formatter settings. Passing lint does not establish clear responsibilities, meaningful names or sufficient logical grouping.

The ownership and lifecycle rules below are project choices informed by these references. Review code against the language guidance and actual call sites, rather than assuming existing code or project instructions are evidence of good style.

## Responsibilities and Organization

- Keep deployment targets at iOS/iPadOS 26 and macOS 26. Use Swift 6 concurrency checking.
- Application roots compose dependencies. Core values and policies do not import SwiftUI, AVKit or database libraries. Features consume core protocols rather than constructing native services.
- Name files after their primary type or coherent responsibility. Small related helper types may stay together. Split code when responsibilities change independently, not at an arbitrary line count; moving an oversized type into extensions alone does not resolve mixed responsibilities.
- Give functions one main level of abstraction. Keep orchestration readable as named steps; extract substantial callbacks and independently meaningful rules. Avoid helpers that merely rename a trivial expression or hide the resource owner.
- Keep a logical member order. For simple types, group dependencies, state, derived values, initialization, actions and cleanup; for larger types, keep each concern's related members together. Use `// MARK: -` only when it improves navigation.
- Put a blank line between methods, initializers and computed properties. Closely related single-line stored properties or enum cases may remain adjacent. Within functions, separate meaningful phases such as validation, preparation, external work and state commits; do not separate every statement.
- Expand nested conditionals and error handling when a one-line form obscures control flow. Simple forwarding methods and obvious early exits can remain concise.

## Names, State and API Contracts

- Prefer clarity at the call site over brevity. Use descriptive argument labels, action verbs for side effects and boolean names that read as predicates. Distinguish request owners, lifecycle tokens, snapshot revisions and playback session IDs; avoid unrelated operations sharing a generic name such as `publish`.
- Prefer `let`, useful type inference and the narrowest access level needed by callers. Expose read-only state when mutations must preserve an invariant, and provide named actions for those mutations.
- Use enums with associated values for mutually exclusive states and their payloads. Keep independent dimensions independent. A flag named `isLoading` must not also mean that loading failed and actions remain blocked.
- Use `guard` for preconditions and early exits. Avoid force unwraps, force casts and `try!` unless an invariant justifies them explicitly. Use `try?` only when failure is intentionally optional or best effort, with the fallback or recovery policy visible.
- Document public APIs with `///`, emphasizing protocol behavior, errors, optional/boolean results and ownership. Self-explanatory enum cases and unchanged protocol implementations need not repeat existing documentation. Document non-obvious private invariants; do not narrate assignments.
- State whether guarded writes rejected an outdated revision or failed with an error, whether streams include an initial snapshot, and which owner cancels work or releases a lease. Keep these contracts beside their declarations, not only in architecture prose or tests.

## SwiftUI and Concurrency

- Keep view bodies focused on composition. Move multi-step business actions into named methods or the owning model/service. Extract cohesive subviews with explicit inputs and actions; retain navigation and presentation state with their actual owner.
- Group SwiftUI dynamic properties logically and keep view-owned `@State` private. Avoid duplicating model state merely for presentation; when a preview or animation snapshot is necessary, make its synchronization and lifetime explicit.
- Share cross-platform interaction rules at their lifecycle owner while keeping platform gestures, native presentation and accessibility in their adapters. Preserve view identity and state lifetime when extracting views.
- Representable updates must not synchronously publish observable state, including through UIKit/AppKit calls that trigger layout or binding callbacks. Defer such effects out of the update pass, coalesce repeated requests, recheck current ownership/visibility, and cancel pending work on teardown. Do not hide a lifecycle problem behind an arbitrary delay.
- Keep all player/transfer/file resources with a visible lifecycle owner. Revalidate session, attempt and revision identities after suspension points. An actor does not make a multi-step asynchronous workflow atomic.
- Prefer compiler-checked `Sendable` conformances. For `@unchecked Sendable`, explain the synchronization or immutability invariant. Consult [Swift actor reentrancy semantics](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy) when reviewing asynchronous state transitions.
- Make task lifetime, cancellation and error reporting explicit. Cancellation and stale-result rejection solve different problems; preserve both where required. Explain intentional best-effort cleanup and recovery after partial persistence.

## Product Contracts and Verification

- Do not use unsupported AVURLAsset header options. Media requests follow the shared HTTPS host policy and carry media headers only.
- Use the [CI-equivalent checks](README.md#ci-and-unsigned-release-builds) for tooling/package tests, formatting and unsigned macOS/iOS Release compilation. CI must not start simulators or run native UI tests.
- Use [local native UI checks](README.md#local-native-ui-checks) for affected interaction and lifecycle changes. Check runtime diagnostics for SwiftUI state-update warnings as well as assertions; compilation and a passing test count alone do not establish warning-free behaviour. Report minimum-OS and physical-device acceptance separately.
- Keep `Packages/SCTVKit/Package.resolved` as the canonical tracked lock. The checker generates the ignored Xcode lock; use `node apple/tool/lockfiles.mjs` from the repository root before direct Xcode use. Preserve locked pin verification and keep machine-specific resolution metadata out of source.
- Use disposable simulators and fixture media; do not alter existing devices or download complete upstream episodes for verification.
- Keep build output, recordings, generated test fixtures, generated Xcode resolution and local signing settings out of Git. Keep per-run evidence under ignored build output.
