# sctv-dl

A shared Web/Tauri desktop app, Kotlin Android client, and Flutter Android/iOS client for browsing and downloading Sichuan TV programmes.

Search the programme library, save favourites, browse broadcasts by date, and preview or download full episodes and clips in standard or smooth quality. Web preferences, viewing history, and programme metadata are saved locally. Web downloads go directly to the browser's download manager; Tauri keeps a durable task queue with pause/resume and local playback.

## Run Locally

For the Kotlin and Jetpack Compose client, open `android/` in Android Studio and follow the [Android README](android/README.md). It connects directly to upstream services and needs no Node deployment. The commands below run the Web app.

For the Flutter Android/iOS client, follow the [Flutter README](flutter/README.md). It includes online/local playback, native background downloads, favourites and viewing history, with its own local data and application ID.

Use Node.js 24.15 or newer and the pnpm version pinned in `package.json`. Run commands from the repository root.

```sh
pnpm install
pnpm dev
```

Open [http://127.0.0.1:5180](http://127.0.0.1:5180). Internet access is required for programme data and video.

Vite serves the frontend and the API/media proxy in one process. Installation uses pnpm's default shared package store.

Web development excludes `android/`, `flutter/` and `src-tauri/` from file watching and discovers dependencies from the root `index.html`. Native build outputs and HTML reports stay outside both scans.

## Build and Serve

```sh
pnpm install --frozen-lockfile
pnpm build
pnpm start
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000). Production uses one Node service for the built frontend, programme APIs, and video streaming. See [Deployment](docs/deployment.md) for configuration and hosting requirements.

## Development

Commands and dependency versions are defined in `package.json`. Run commands from the repository root.

| Command                             | Purpose                                         |
| ----------------------------------- | ----------------------------------------------- |
| `pnpm dev`                          | Frontend and proxies at port 5180               |
| `pnpm typecheck`                    | Browser and Node TypeScript checks              |
| `pnpm test`                         | Vitest suite                                    |
| `pnpm lint` / `pnpm lint:fix`       | Check or fix ESLint and CSS rules               |
| `pnpm format` / `pnpm format:check` | Format or check source and documentation        |
| `pnpm check`                        | Type checking, tests, lint, and formatting      |
| `pnpm build`                        | Type checking and production frontend build     |
| `pnpm preview`                      | Built app and local proxies at port 4173        |
| `pnpm start`                        | Production Node service; requires `dist/`       |
| `pnpm desktop:dev`                  | Run the desktop client with frontend hot reload |
| `pnpm desktop:check`                | Check Rust formatting, Clippy, and native tests |
| `pnpm desktop:build`                | Build the host platform's desktop package       |

The development and preview ports are strict. If 5180 is occupied, choose a free port explicitly, for example `pnpm dev --port 5181`. Restart Vite after configuration changes. Preview is for local build verification.

## CI and Dependency Updates

[GitHub Actions](.github/workflows/ci.yml) runs on pull requests and pushes to `main`, and can also be started manually. It installs the pnpm version from `package.json` with a frozen lockfile, then runs `pnpm check` and `pnpm build` on Ubuntu with Node.js 24.15.0 and 26. Superseded runs are cancelled, and the shared pnpm store is cached between runs.

[Dependabot](.github/dependabot.yml) checks npm dependencies, Android Gradle dependencies and the Gradle Wrapper, and GitHub Actions every Monday at 09:00 Asia/Shanghai. The `/android` entry includes the version catalogue, declared modules, and included `build-logic` build. Minor and patch updates are grouped by production dependencies, development dependencies, Android dependencies, and actions; major updates receive separate pull requests. Updates require review and are not merged automatically.

[Android CI](.github/workflows/android.yml) also submits the resolved Gradle dependency graph in a separate job on pushes to `main` and manual runs on `main`. Release app dependencies are labelled `runtime`; other dependencies are labelled `development`. See [Android Dependency Security](android/README.md#dependency-security) for scope rules and alert handling. Only that job has `contents: write`; pull-request checks keep read-only permissions. Dependabot alerts and security updates are repository settings enabled separately from the YAML configuration. Security updates open reviewable pull requests and do not enable automatic merging.

Both configurations take effect after they reach the default branch on GitHub. Dependabot's update parser handles multi-document pnpm lockfiles, but GitHub's dependency graph and security alerts still have a [reported pnpm 12 limitation](https://github.com/dependabot/dependabot-core/issues/15904). Do not rely on an empty dependency graph as evidence that dependencies are secure.

## Documentation

| Document                                                                            | Purpose                                                            |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| [Agent Instructions](AGENTS.md)                                                     | Project constraints, coding conventions, and verification          |
| [Architecture](docs/architecture.md)                                                | Module ownership, data flow, and important behaviour               |
| [Web Styling](docs/styling.md)                                                      | Native CSS conventions, theme ownership, and UI verification       |
| [Deployment](docs/deployment.md)                                                    | Production service, configuration, and operations                  |
| [Upstream API](docs/upstream-api.md)                                                | Programme endpoints, video fields, and proxy contracts             |
| [Android Client Design](docs/android-client-design.md)                              | Native Compose product, architecture, and acceptance criteria      |
| [Feature Validation](docs/web-desktop-feature-validation.md)                        | History, durable downloads, cache, and current acceptance evidence |
| [Android Client](android/README.md)                                                 | Native setup, modules, downloads, playback, and verification       |
| [Flutter Client](flutter/README.md)                                                 | Android/iOS setup, ownership, downloads, playback and checks       |
| [Flutter Mobile Design](docs/superpowers/specs/2026-10-16-flutter-mobile-design.md) | Approved Android/iOS scope, architecture, and acceptance criteria  |
| [Flutter Validation](docs/flutter-validation.md)                                    | Actual runtime/build evidence and remaining device acceptance      |

The [Desktop Development guide](docs/desktop.md) describes the integrated Tauri client, native commands, CI, and platform validation limits. Windows and macOS work is tracked in the [implementation plan](docs/superpowers/plans/2026-10-16-tauri-desktop.md) and its [design brief](docs/superpowers/specs/2026-10-16-tauri-desktop-design.md); [media validation](docs/desktop-media-validation.md) records actual evidence and pending platform checks.
