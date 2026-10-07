# sctv-dl

A Web app for browsing and downloading Sichuan TV programmes.

Search the programme library, save favourites, browse broadcasts by date, and preview or download full episodes and clips in standard or smooth quality. Preferences are saved in the browser. Downloads go directly to the browser's download manager.

## Run Locally

Use Node.js 24.15 or newer and the pnpm version pinned in `package.json`. Run commands from the repository root.

```sh
pnpm install
pnpm dev
```

Open [http://127.0.0.1:5180](http://127.0.0.1:5180). Internet access is required for programme data and video.

Vite serves the frontend and the API/media proxy in one process. Installation uses pnpm's default shared package store.

## Build and Serve

```sh
pnpm install --frozen-lockfile
pnpm build
pnpm start
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000). Production uses one Node service for the built frontend, programme APIs, and video streaming. See [Deployment](docs/deployment.md) for configuration and hosting requirements.

## Development

Commands and dependency versions are defined in `package.json`. Run commands from the repository root.

| Command                             | Purpose                                     |
| ----------------------------------- | ------------------------------------------- |
| `pnpm dev`                          | Frontend and proxies at port 5180           |
| `pnpm typecheck`                    | Browser and Node TypeScript checks          |
| `pnpm test`                         | Vitest suite                                |
| `pnpm lint` / `pnpm lint:fix`       | Check or fix ESLint and Tailwind rules      |
| `pnpm format` / `pnpm format:check` | Format or check source and documentation    |
| `pnpm check`                        | Type checking, tests, lint, and formatting  |
| `pnpm build`                        | Type checking and production frontend build |
| `pnpm preview`                      | Built app and local proxies at port 4173    |
| `pnpm start`                        | Production Node service; requires `dist/`   |

The development and preview ports are strict. If 5180 is occupied, choose a free port explicitly, for example `pnpm dev --port 5181`. Restart Vite after configuration changes. Preview is for local build verification.

## Documentation

| Document                             | Purpose                                                   |
| ------------------------------------ | --------------------------------------------------------- |
| [Agent Instructions](AGENTS.md)      | Project constraints, coding conventions, and verification |
| [Architecture](docs/architecture.md) | Module ownership, data flow, and important behaviour      |
| [Deployment](docs/deployment.md)     | Production service, configuration, and operations         |
| [Upstream API](docs/upstream-api.md) | Programme endpoints, video fields, and proxy contracts    |
