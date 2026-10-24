# Repository Maintenance

This guide owns repository-wide verification, CI and dependency updates. Runtime structure belongs to [Architecture](architecture.md); Node hosting belongs to [Deployment](deployment.md); native build and distribution details belong to the platform guides linked from [README](../README.md).

## Verification by Change

| Change                  | Checks                                                                                                                                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Documentation only      | `pnpm format:check`, `pnpm docs:check`, referenced scripts/configuration and `git diff --check`; no application build is needed.                                                                 |
| Web or Node behaviour   | `pnpm check` and `pnpm build`; meaningful regression tests beside their owner.                                                                                                                   |
| Web UI                  | The above plus desktop/narrow browser checks, themes, keyboard and loading/empty/error states.                                                                                                   |
| Tauri Rust              | `pnpm desktop:check` and `pnpm test:desktop`; add Web checks for adapters, shared contracts or integration changes. See [Desktop Development](desktop.md).                                       |
| SwiftUI Apple           | Run [CI-equivalent checks](../apple/README.md#ci-and-unsigned-release-builds); add [local UI checks](../apple/README.md#local-native-ui-checks) for affected interactions and lifecycle changes. |
| Kotlin Android          | Follow [Android build and device checks](../android/README.md); shared Web/tooling changes also require Web checks.                                                                              |
| Flutter or native hosts | Follow [Flutter checks](../flutter/README.md); native plugin/host changes need relevant compilation and disposable-runtime checks.                                                               |

Use controlled upstream/media fixtures and disposable devices. HEAD or a small Range request is enough to check live media transport. Test results, compiler success, device acceptance and signed distribution are separate evidence. Keep machine-specific paths, run logs, screenshots and build products out of tracked source.

## CI scope

Routine CI must not boot simulators/emulators, require a connected device or drive native GUI interactions. Host-side unit/package/widget tests and compilation remain in CI; native UI, instrumentation execution and device acceptance use explicit local commands.

| Workflow                                                  | Automated scope                                                                                                                               |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| [Web and repository quality](../.github/workflows/ci.yml) | Vitest, Web build, lint, formatting, documentation links and workflow validation                                                              |
| [Android](../.github/workflows/android.yml)               | Gradle checks/JVM tests/lint, app builds and baseline/benchmark APK compilation                                                               |
| [Flutter](../.github/workflows/flutter.yml)               | Generated-source checks, Dart formatting/analysis, unit/widget tests, Android instrumentation compilation and Android/iOS release compilation |
| [Apple](../.github/workflows/apple.yml)                   | Node tooling tests, Swift formatting/package tests and unsigned macOS/iOS Release compilation                                                 |
| [Desktop](../.github/workflows/desktop.yml)               | Adapter/contract and Rust tests, native checks and platform packaging                                                                         |

Compiling an instrumentation or UI target does not execute it. Toolchain versions, runner images and trigger paths are defined in the workflows; platform guides own local commands.

[GitHub Actions](../.github/workflows/ci.yml) runs on pull requests and pushes to `main`, and can also be started manually. It installs the pnpm version from `package.json` with a frozen lockfile, then runs tests and `pnpm build` on Ubuntu with Node.js 24.15.0 and 26. A separate repository-quality job runs ESLint, Prettier, local Markdown file/heading validation and actionlint once per run. Superseded runs are cancelled, and the shared pnpm store is cached between runs.

[Android CI](../.github/workflows/android.yml) also submits the resolved Gradle dependency graph in a separate job on pushes to `main` and manual runs on `main`. Release app dependencies are labelled `runtime`; other dependencies are labelled `development`. See [Android Dependency Security](../android/README.md#dependency-security) for scope rules and alert handling. Only that job has `contents: write`; pull-request checks keep read-only permissions. Dependabot alerts and security updates are repository settings enabled separately from the YAML configuration. Security updates open reviewable pull requests and do not enable automatic merging.

Desktop validation runs for shared frontend/server/contracts, native Rust/assets, tooling and build-configuration changes. Documentation-only and Android/Flutter-only changes skip that workflow. Windows/macOS run `pnpm test:desktop` for native adapters, shared IPC contracts and release-source rules; the Ubuntu matrix owns the complete Web/server suite. Native formatting, Clippy, tests, signing-script fixtures, frontend compilation and installer packaging stay on their owning OS. Both validation and signed release builds also run a locked `cargo +1.90.0 check --all-targets` against the declared Rust minimum. Keep that command aligned with `rust-version` when changing the supported compiler floor.

Workflow-level path filtering is not a required-check aggregator. If branch protection is added later, use an always-reported gate that distinguishes irrelevant jobs from failures; do not require a workflow that can be skipped by paths.

Apple, Desktop and Flutter have their own workflows and native prerequisites; their platform guides describe packaging and signing. A workflow definition or local command passing does not establish a successful hosted run. Review job results and artifacts for the exact commit being released.

## Dependency updates

[Dependabot](../.github/dependabot.yml) checks npm dependencies, Tauri Cargo dependencies, Android/Flutter Gradle dependencies and wrappers, Flutter pub dependencies, Apple Swift package dependencies, and GitHub Actions every Monday at 09:00 Asia/Shanghai. The `/android` entry includes the version catalogue, declared modules, and included `build-logic` build. Flutter native updates cover `/flutter/android`; hosted player plugins are updated through Pub and the application lockfile. There is no vendored player override. See [Flutter dependencies](../flutter/README.md#player-dependency-and-licenses) for native plugin limitations. Minor and patch updates are grouped by production dependencies, development dependencies, Android dependencies, Flutter dependencies, desktop Rust dependencies, Flutter native dependencies, Apple dependencies, and actions; major updates receive separate pull requests. Updates require review and are not merged automatically.

Apple uses the package `Package.resolved` as the canonical tracked Swift lock. The checker generates the ignored Xcode lock from those pins and rejects resolution drift after builds. See [Apple dependencies](../apple/README.md#dependencies-and-fixtures) before opening Xcode directly or updating package requirements.

Scheduled configuration takes effect from the default branch. Check dependency submission/parser results when updating lockfile formats; an empty dependency graph is not evidence that dependencies are secure.

## Workflow and Documentation Checks

Run `pnpm docs:check` to validate links to local files and headings in root/platform Markdown and `docs/`. It uses remark's Markdown/GFM parser and link validator, does not rewrite files, and fails on warnings. External website availability is outside this offline check; vendored dependency documentation remains maintained with that dependency. `pnpm check` includes the documentation check.

Run `pnpm ci:lint` with Go installed to execute the pinned actionlint release. CI selects Go 1.27.2; Go downloads the pinned tool and verifies module checksums. actionlint checks workflow structure, expressions, jobs, action inputs and runner labels; ShellCheck runs too when available. This validation does not exercise hosted runners, credentials or signed output. Prettier remains responsible for YAML/Markdown formatting.

## Documentation Ownership

README is the project entry point and documentation index. Platform READMEs own setup, build, test and troubleshooting commands; `docs/` owns durable architecture, product and operating contracts. Coding instructions belong to root/platform `AGENTS.md`. Keep dependency patch provenance and licenses with the patched dependency.

When a plan or investigation finishes, move reusable constraints and procedures into the owning guide, remove superseded proposals and execution checklists, and update incoming links. Store per-run evidence with ignored build outputs or CI/release artifacts. Git history retains removed plans and verification records; do not create a second tracked log archive.
