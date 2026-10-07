# sctv-dl

Browse real Sichuan TV programmes, search and save favourites, select full episodes or clips by broadcast date, and download them directly in standard or smooth quality. Theme, preview quality preferences, and favourites are stored locally in the browser.

## Development

Use Node.js 24.15+ (verified with 26.10.0) and pnpm 10.28.2. Run all commands from the project root.

```powershell
pnpm install
pnpm dev
```

Open http://127.0.0.1:5180 . An internet connection is required to access the programme service. `pnpm dev` starts one Vite process that serves both the frontend and the proxy middleware; no separate server command is needed.

Installation uses pnpm's default machine-wide package store. The repository does not override `store-dir`, so other projects can reuse cached packages.

The interface uses Tailwind CSS 4 through the official Vite plugin. Short utility combinations stay in Vue templates; complex and repeated component styles use scoped `@apply` rules with `@reference` to the shared theme. `src/styles/global.css` defines theme tokens, base rules, shared presentation classes, and named transitions. Naive UI and Artplayer retain their own library styles.

Development uses Vite's regular module-based hot updates and automatic dependency pre-bundling. Experimental bundled dev mode is disabled because its rebuilds interrupted editing with a bundling page. Restart `pnpm dev` after changing Vite configuration.

```powershell
pnpm check
pnpm build
pnpm preview
```

`build` runs TypeScript checks before generating `dist/`. `preview` serves the production build at http://127.0.0.1:4173 with the same local proxy.

`pnpm lint` checks Tailwind class names in Vue templates, bound class expressions, CSS files, and Vue `<style>` blocks. `pnpm lint:fix` applies canonical names (for example, `w-[232px]` becomes `w-58`), official class ordering, and duplicate removal. Conflicting and deprecated utilities are also reported. Prettier handles whitespace and line wrapping. VS Code workspace settings enable ESLint fixes on save and recommend the ESLint and Tailwind extensions. Tailwind IntelliSense retains its own diagnostics.

## Project Structure

- `src/app/` / `src/layouts/`: routing, theme configuration, and application layout.
- `src/features/programmes/`: programme APIs, validation, catalogue cache, archive logic, and components.
- `src/features/downloads/`: quality resolution, safe filenames, and direct browser download handoff.
- `src/features/settings/`: preference validation and settings.
- `src/shared/` / `src/styles/`: shared logic and base styles.
- `src/components/`: reusable cover images and state feedback.
- `server/`: production HTTP service, shared API and streaming media proxies, and Vite integration.

See [Coding Conventions](CONTRIBUTING.md) and [Architecture and Library Decisions](docs/architecture.md) for module responsibilities, formatting rules, and the rationale for retained custom logic.

## Download Behaviour

Video previews use Artplayer with Chinese playback controls, speed settings, keyboard shortcuts, picture-in-picture, and fullscreen. When a programme has distinct standard and smooth variants, the settings menu also provides quality selection while retaining the playback position. Playback begins when requested, and closing a preview releases the player. The initial quality follows the saved preference with an available-variant fallback. UI motion respects the system's reduced-motion preference, and the theme follows the system by default.

Use a content row's download button or select multiple rows and choose the batch download action above the list. Both open a quality dropdown; selecting a quality checks video availability with HEAD and immediately hands each available file to the browser. A notification reports the handoff or failure while keeping the current page. There is no separate task page or persistent download queue. Download buttons are temporarily disabled during preparation to prevent repeated clicks; afterward, a file can be downloaded again or retried from its row. Dismissing the menu starts no download. Download quality is chosen per operation, while the saved quality preference controls initial video preview quality.

The browser download manager owns progress, the destination directory, pause, cancellation, resume, and the final result. A handoff means that a save was requested; it does not mean the download finished. Batch downloads may require the browser to allow multiple files. A failed video does not stop the remaining batch; the notification reports the successful handoff count, failure count, and first failed video's error.

Content rows show available variants, and unavailable menu choices are disabled. In a mixed batch, missing variants fall back to the available quality, with a notification explaining the fallback for handed-off files. Selection is disabled only when both video variants are missing. Full-episode selection matches the programme name and broadcast date in the title; it does not assume the first item is a full episode. Filenames include the date, title, and actual quality. Large videos are streamed rather than fully buffered in page memory.

## APIs and Proxies

Upstream service: `https://gw.scgchc.com`.

- `GET /app/v1/programs?page=0&size=100`
- `GET /app/v1/programs/{programmeId}/dates/list`
- `GET /app/v1/programs/{programmeId}/dates/{dateId}/contents/list`

`dateId` is the string ID returned by the service, not the date text. All IDs are retained as strings. `video` contains the standard variant; `videoStandard` contains the smooth variant.

The programme APIs returned `Access-Control-Allow-Origin: *` during verification on 2026-10-06, so programme metadata can currently be requested directly from a browser. The default configuration keeps these requests behind `/api` for a consistent local origin. Set `VITE_API_BASE=https://gw.scgchc.com` before building to request metadata directly.

The tested video returned HTTP 403 without a Referer and HTTP 200 with `Referer: https://scgc.video.play/`. A page cannot use [Fetch's referrer option](https://developer.mozilla.org/en-US/docs/Web/API/RequestInit#referrer) to supply an arbitrary foreign origin. The shared `/media?url=...` middleware therefore adds the required header, forwards Range / If-Range, and streams the response. The media proxy accepts only HTTPS MP4 URLs on `fscgc.scgchc.com` and rejects other hosts, explicit nondefault ports, credentials, and redirects. Downloads receive a safely encoded Content-Disposition filename.

## Deployment

Deploy one long-running Node.js service that serves the built frontend, programme APIs, and video streams on the same port:

```powershell
pnpm install --frozen-lockfile
pnpm build
pnpm start
```

Open http://127.0.0.1:3000 locally. The production entry is `server/index.ts`; it runs directly with Node's stable TypeScript support and does not load Vite. Keep `dist/`, `server/`, and the package manifests together when deploying. If the frontend was built elsewhere, install runtime dependencies with `pnpm install --prod --frozen-lockfile` and start the service without running the build again. Vite preview remains a local build-verification tool.

`pnpm start` loads an optional `.env` file. `HOST` defaults to `0.0.0.0` and `PORT` defaults to `3000`; environment variables supplied by the host override `.env`. `VITE_API_BASE` and `VITE_MEDIA_BASE` are build-time settings, so keep their default `/api` and `/media` values for this single-origin deployment. Changing either requires rebuilding the frontend.

The service supports direct Vue Router navigation, revalidates HTML with ETags, and caches Vite's hashed assets. `GET /healthz` returns `{"status":"ok"}` without contacting the upstream service. Startup fails clearly when the frontend build is missing or the port is invalid. SIGINT and SIGTERM stop accepting requests and allow active transfers up to 30 seconds to finish.

The server forwards media with backpressure and does not save video files or maintain download jobs. Transfers consume the deployment host's outgoing bandwidth. If the hosting platform supplies HTTPS or a reverse proxy, it must allow streaming responses, Range requests, and long downloads. The existing allowlist restricts requests to the programme APIs and verified MP4 CDN.

Static hosting alone cannot provide working video downloads under the verified Referer restriction. A future desktop or mobile client can make these requests through its native HTTP implementation without a local HTTP proxy process.

Set `VITE_API_BASE` / `VITE_MEDIA_BASE` from `.env.example` before building to use different service endpoints. This version does not include a Rust SDK, desktop shell, authentication, or live-stream parsing.
