# Repository Maintenance

This guide owns repository-wide verification, CI and dependency updates. Runtime structure belongs to [Architecture](architecture.md); Node hosting belongs to [Deployment](deployment.md); native build and distribution details belong to the platform guides linked from [README](../README.md).

## Verification by Change

| Change                  | Checks                                                                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Documentation only      | `pnpm format:check`, local file/heading links, referenced scripts/configuration and `git diff --check`; no application build is needed. |
| Web or Node behaviour   | `pnpm check` and `pnpm build`; meaningful regression tests beside their owner.                                                          |
| Web UI                  | The above plus desktop/narrow browser checks, themes, keyboard and loading/empty/error states.                                          |
| Tauri Rust              | `pnpm desktop:check`; add Web checks for adapters, shared contracts or integration changes. See [Desktop Development](desktop.md).      |
| Kotlin Android          | Follow [Android build and device checks](../android/README.md); shared Web/tooling changes also require Web checks.                     |
| Flutter or native hosts | Follow [Flutter checks](../flutter/README.md); native plugin/host changes need relevant compilation and disposable-runtime checks.      |

Use controlled upstream/media fixtures and disposable devices. HEAD or a small Range request is enough to check live media transport. Test results, compiler success, device acceptance and signed distribution are separate evidence. Keep machine-specific paths, run logs, screenshots and build products out of tracked source.

## CI and Dependency Updates

[GitHub Actions](../.github/workflows/ci.yml) runs on pull requests and pushes to `main`, and can also be started manually. It installs the pnpm version from `package.json` with a frozen lockfile, then runs `pnpm check` and `pnpm build` on Ubuntu with Node.js 24.15.0 and 26. Superseded runs are cancelled, and the shared pnpm store is cached between runs.

[Dependabot](../.github/dependabot.yml) checks npm dependencies, Tauri Cargo dependencies, Android/Flutter Gradle dependencies and wrappers, Flutter pub dependencies, and GitHub Actions every Monday at 09:00 Asia/Shanghai. The `/android` entry includes the version catalogue, declared modules, and included `build-logic` build. Flutter native updates cover `/flutter/android` and the vendored player's Android build. Review those plugin changes against its patch provenance; Pub updates do not replace the local source override. Minor and patch updates are grouped by production dependencies, development dependencies, Android dependencies, Flutter dependencies, desktop Rust dependencies, Flutter native dependencies, and actions; major updates receive separate pull requests. Updates require review and are not merged automatically.

[Android CI](../.github/workflows/android.yml) also submits the resolved Gradle dependency graph in a separate job on pushes to `main` and manual runs on `main`. Release app dependencies are labelled `runtime`; other dependencies are labelled `development`. See [Android Dependency Security](../android/README.md#dependency-security) for scope rules and alert handling. Only that job has `contents: write`; pull-request checks keep read-only permissions. Dependabot alerts and security updates are repository settings enabled separately from the YAML configuration. Security updates open reviewable pull requests and do not enable automatic merging.

Scheduled configuration takes effect from the default branch. Check dependency submission/parser results when updating lockfile formats; an empty dependency graph is not evidence that dependencies are secure.

Desktop and Flutter have their own workflows and native prerequisites; their platform guides describe packaging and signing. A workflow definition or local command passing does not establish a successful hosted run. Review job results and artifacts for the exact commit being released.

## Documentation Ownership

README is the project entry point and documentation index. Platform READMEs own setup, build, test and troubleshooting commands; `docs/` owns durable architecture, product and operating contracts. Coding instructions belong to root/platform `AGENTS.md`. Keep dependency patch provenance and licenses with the patched dependency.

When a plan or investigation finishes, move reusable constraints and procedures into the owning guide, remove superseded proposals and execution checklists, and update incoming links. Store per-run evidence with ignored build outputs or CI/release artifacts. Git history retains removed plans and verification records; do not create a second tracked log archive.
