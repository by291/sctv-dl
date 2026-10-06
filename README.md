# sctv-dl

Browse real Sichuan TV programmes, search and save favourites, select full episodes or clips by broadcast date, choose standard or smooth quality, and add items to a download queue. Theme, quality preferences, favourites, and task metadata are stored locally in the browser.

## Development

Use Node.js 24.12+ (verified with 26.10.0) and pnpm 10.28.2. Run all commands from the project root.

```powershell
pnpm install
pnpm dev
```

Open http://127.0.0.1:5180 . An internet connection is required to access the programme service. `pnpm dev` starts one Vite process that serves both the frontend and the proxy middleware; no separate server command is needed.

```powershell
pnpm check
pnpm build
pnpm preview
```

`build` runs TypeScript checks before generating `dist/`. `preview` serves the production build at http://127.0.0.1:4173 with the same local proxy.

## Project Structure

- `src/app/` / `src/layouts/`: routing, theme configuration, and application layout.
- `src/features/programmes/`: programme APIs, validation, catalogue cache, archive logic, and components.
- `src/features/downloads/`: task models, validation, queue management, and browser download handoff.
- `src/features/settings/`: preference validation and settings.
- `src/shared/` / `src/styles/`: shared logic and base styles.
- `src/components/`: reusable cover images and state feedback.
- `server/`: API and streaming media proxies for Vite development and preview.

See [Coding Conventions](CONTRIBUTING.md) and [Architecture and Library Decisions](docs/architecture.md) for module responsibilities, formatting rules, and the rationale for retained custom logic.

## Download Behaviour

Video previews use Artplayer with Chinese playback controls, speed settings, keyboard shortcuts, picture-in-picture, and fullscreen. Playback begins when requested, and closing a preview releases the player. If the selected video variant is unavailable, the preview uses the same fallback as the download queue. UI motion respects the system's reduced-motion preference.

Select content on the programme details page and add it to the queue, then start downloads from the task page. The application uses HEAD to check video availability before handing the download to the browser. A `handed-off` task means that a save was requested; it does not mean the download finished. The browser download manager owns progress, the destination directory, pause, cancellation, resume, and the final result. Batch downloads may require the browser to allow multiple files.

Tasks are deduplicated by content ID and actual quality. If the requested quality is missing, the available alternative is used and shown in the content row and task. Selection is disabled only when both video variants are missing. Full-episode selection matches the programme name and broadcast date in the title; it does not assume the first item is a full episode. Filenames include the date, title, and actual quality. Large videos are streamed rather than fully buffered in page memory.

## APIs and Proxies

Upstream service: `https://gw.scgchc.com`.

- `GET /app/v1/programs?page=0&size=100`
- `GET /app/v1/programs/{programmeId}/dates/list`
- `GET /app/v1/programs/{programmeId}/dates/{dateId}/contents/list`

`dateId` is the string ID returned by the service, not the date text. All IDs are retained as strings. `video` contains the standard variant; `videoStandard` contains the smooth variant.

The programme APIs returned `Access-Control-Allow-Origin: *` during verification on 2026-10-06, so programme metadata can currently be requested directly from a browser. The default configuration keeps these requests behind `/api` for a consistent local origin. Set `VITE_API_BASE=https://gw.scgchc.com` before building to request metadata directly.

The tested video returned HTTP 403 without a Referer and HTTP 200 with `Referer: https://scgc.video.play/`. A page cannot use [Fetch's referrer option](https://developer.mozilla.org/en-US/docs/Web/API/RequestInit#referrer) to supply an arbitrary foreign origin. The local `/media?url=...` middleware therefore adds the required header, forwards Range / If-Range, and streams the response. The media proxy accepts only HTTPS MP4 URLs on `fscgc.scgchc.com` and rejects other hosts, explicit nondefault ports, credentials, and redirects. Downloads receive a safely encoded Content-Disposition filename.

## Deployment

The Vite proxies run only with `dev` and `preview`; **they are not included in `dist/`**. A production host needs the `/media` route, an `/api` route if metadata uses the default proxy configuration, and a history fallback to `index.html` for Vue Router. One application server can serve both the static build and these routes on the same port; a second process or separately deployed proxy is not required. A production server is not included yet, and Vite preview is only for local build verification.

Static hosting alone cannot provide working video downloads under the verified Referer restriction. A future desktop or mobile client can make these requests through its native HTTP implementation without a local HTTP proxy process.

Set `VITE_API_BASE` / `VITE_MEDIA_BASE` from `.env.example` before building to use different service endpoints. This version does not include a production server, Rust SDK, desktop shell, authentication, or live-stream parsing.
