# sctv-dl

Browse real Sichuan TV programmes, search and save favourites, select full episodes or clips by broadcast date, choose standard or smooth quality, and add items to a download queue. Theme, quality preferences, favourites, and task metadata are stored locally in the browser.

## Development

Use Node.js 24.12+ (verified with 26.10.0) and pnpm 10.28.2. Run all commands from the project root.

```powershell
pnpm install
pnpm dev
```

Open http://127.0.0.1:5180 . An internet connection is required to access the programme service.

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

Select content on the programme details page and add it to the queue, then start downloads from the task page. The application uses HEAD to check video availability before handing the download to the browser. A `handed-off` task means that a save was requested; it does not mean the download finished. The browser download manager owns progress, the destination directory, pause, cancellation, resume, and the final result. Batch downloads may require the browser to allow multiple files.

Tasks are deduplicated by content ID and actual quality. If the requested quality is missing, the available alternative is used and shown in the content row and task. Selection is disabled only when both video variants are missing. Full-episode selection matches the programme name and broadcast date in the title; it does not assume the first item is a full episode. Filenames include the date, title, and actual quality. Large videos are streamed rather than fully buffered in page memory.

## APIs and Proxies

Upstream service: `https://gw.scgchc.com`.

- `GET /app/v1/programs?page=0&size=100`
- `GET /app/v1/programs/{programmeId}/dates/list`
- `GET /app/v1/programs/{programmeId}/dates/{dateId}/contents/list`

`dateId` is the string ID returned by the service, not the date text. All IDs are retained as strings. `video` contains the standard variant; `videoStandard` contains the smooth variant.

Video requests require `Referer: https://scgc.video.play/`. Browsers cannot set this header directly, so the local `/media?url=...` service adds it, forwards Range / If-Range, and streams the response. The media proxy accepts only HTTPS MP4 URLs on `fscgc.scgchc.com` and rejects other hosts, explicit nondefault ports, credentials, and redirects. It is not an unrestricted proxy. Downloads receive a safely encoded Content-Disposition filename.

## Deployment

The Vite proxies run only with `dev` and `preview`; **they are not included in `dist/`**. Production deployments need matching `/api` and `/media` services and a history fallback to `index.html` for Vue Router. Hosting the static files alone does not provide the download service.

Set `VITE_API_BASE` / `VITE_MEDIA_BASE` from `.env.example` before building to use different service endpoints. This version does not include a production server, Rust SDK, desktop shell, authentication, or live-stream parsing.
