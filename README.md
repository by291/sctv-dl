# sctv-dl

A shared Web/Tauri desktop app, Kotlin Android client, and Flutter Android/iOS client for browsing and downloading Sichuan TV programmes.

Search the programme library, save favourites, browse broadcasts by date, and preview or download full episodes and clips in standard or smooth quality. Web preferences, viewing history, and programme metadata are saved locally. Web downloads go directly to the browser's download manager; Tauri keeps a durable task queue with pause/resume and local playback.

## Clients

| Client                  | Source                         | Setup                                            |
| ----------------------- | ------------------------------ | ------------------------------------------------ |
| Web                     | `src/`, `server/`, `shared/`   | Commands below; production uses one Node service |
| Desktop (Windows/macOS) | Shared Vue UI and `src-tauri/` | [Desktop Development](docs/desktop.md)           |
| Kotlin Android          | `android/`                     | [Android README](android/README.md)              |
| Flutter Android/iOS     | `flutter/`                     | [Flutter README](flutter/README.md)              |

Native clients connect directly to upstream services and require no Node deployment. Each installation keeps its own local state; cross-client synchronization or automatic data import is not provided.

## Run Locally

The following commands run the Web app.

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

| Command                             | Purpose                                                        |
| ----------------------------------- | -------------------------------------------------------------- |
| `pnpm dev`                          | Frontend and proxies at port 5180                              |
| `pnpm typecheck`                    | Browser and Node TypeScript checks                             |
| `pnpm test`                         | Vitest suite                                                   |
| `pnpm lint` / `pnpm lint:fix`       | Check or fix ESLint and CSS rules                              |
| `pnpm format` / `pnpm format:check` | Format or check source and documentation                       |
| `pnpm docs:check`                   | Check local Markdown file and heading links                    |
| `pnpm ci:lint`                      | Validate GitHub Actions with pinned actionlint (requires Go)   |
| `pnpm check`                        | Type checking, tests, lint, formatting and documentation links |
| `pnpm build`                        | Type checking and production frontend build                    |
| `pnpm preview`                      | Built app and local proxies at port 4173                       |
| `pnpm start`                        | Production Node service; requires `dist/`                      |
| `pnpm desktop:dev`                  | Run the desktop client with frontend hot reload                |
| `pnpm desktop:check`                | Check Rust formatting, Clippy, and native tests                |
| `pnpm desktop:build`                | Build the host platform's desktop package                      |

The development and preview ports are strict. If 5180 is occupied, choose a free port explicitly, for example `pnpm dev --port 5181`. Restart Vite after configuration changes. Preview is for local build verification.

## CI and Dependency Updates

See [Repository Maintenance](docs/maintenance.md) for verification by change, CI workflows and dependency updates. Platform guides document their native build and release checks.

## Documentation

| Document                                      | Responsibility                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------- |
| [Web Architecture](docs/architecture.md)      | Shared Vue frontend, Node services, module ownership, storage and player lifecycles |
| [Web Styling](docs/styling.md)                | CSS ownership, themes, responsive layout and motion                                 |
| [Upstream API](docs/upstream-api.md)          | Shared endpoint, ID, quality, header and proxy contracts                            |
| [Deployment](docs/deployment.md)              | Node production service, configuration, hosting and operations                      |
| [Desktop Development](docs/desktop.md)        | Tauri architecture, native commands/resources, installers and release checks        |
| [Android Architecture](docs/android.md)       | Kotlin/Compose product, module boundaries, persistence and native lifecycles        |
| [Flutter Architecture](docs/flutter.md)       | Flutter product, data boundaries, navigation, native transfers and playback         |
| [Repository Maintenance](docs/maintenance.md) | Verification scope, CI, dependency updates and documentation ownership              |
| [Android Setup](android/README.md)            | Toolchain, builds, device tests and performance tooling                             |
| [Flutter Setup](flutter/README.md)            | Toolchain, builds, native fixtures and platform limitations                         |
| [Agent Instructions](AGENTS.md)               | Contribution rules and links to platform-specific coding conventions                |

Each subject has one maintained owner. Completed plans and one-time verification logs are kept in Git history rather than duplicated in `docs/`.
