# Desktop Development

The repository contains a Tauri 2 desktop scaffold and the shared contracts/Web adapters needed for native integration. The installed application currently loads the shared interface, but native programme services, playback transport, downloads, and settings are not connected. It is not a complete desktop client.

## Commands and Prerequisites

Use the Node/pnpm versions from [README](../README.md), Rust with Cargo, and the [official platform prerequisites](https://v2.tauri.app/start/prerequisites/). The generated Cargo manifest declares Rust 1.90; this initial batch was built with Rust 1.98.0. The declared minimum compiler has not been separately tested.

Run from the repository root:

```sh
pnpm desktop:dev
pnpm desktop:build
```

Development starts Vite on port 5180. At this stage it still uses the Web business adapters and Node middleware. Production bundles `dist/` into the application using Tauri's default asset protocol. A packaged shell can display the interface without Node, but programme requests cannot work there until the native adapter phase is implemented.

To build only a local macOS application bundle:

```sh
pnpm desktop:build --bundles app
```

The output is under `src-tauri/target/release/bundle/`. macOS builds use an ad-hoc signature for local validation; they are not notarized public releases. The proposed macOS minimum is 13.0. Windows configuration selects the NSIS installer. Windows builds and runtime behaviour remain unverified in this batch.

Rust checks can be run independently:

```sh
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --locked -- -D warnings
cargo test --manifest-path src-tauri/Cargo.toml --locked
```

The scaffold contains no native business tests yet; successful Cargo checks currently verify compilation and linting of the shell only. Native build products and generated schemas are ignored. Application icons are generated from `public/favicon.svg` with `pnpm tauri icon public/favicon.svg`; keep only the desktop icon outputs when regenerating them.

## Current Integration Boundary

- `shared/contracts/` contains application DTO schemas and inferred types shared by browser and Node. `shared/fixtures/` contains examples for future equivalent Rust tests.
- `src/shared/platform/` defines injectable programme, playback, download, and settings ports. Components consume ports; native API imports in Vue components are rejected by ESLint.
- `src/platform/web-platform.ts` composes the current Web adapters. Environment selection and the Rust adapters are later phases; startup does not silently pretend a native implementation exists.
- Node exposes normalized `/client-api/v1` routes alongside the preserved `/api` and `/media` proxies. See [Upstream API](upstream-api.md) for contracts and [Deployment](deployment.md) for configuration migration.
- Browser downloads still use HEAD preflight and browser handoff. Native task progress, files, directory selection, and exit confirmation remain future work.

The [implementation plan](superpowers/plans/2026-10-16-tauri-desktop.md) tracks phase status. [Media validation](desktop-media-validation.md) records what was actually checked and what remains open.
