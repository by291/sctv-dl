# Deployment

Run one long-lived Node service for the frontend, programme API proxy, and streaming media proxy. The service requires Node.js 24.15+; the pnpm version is pinned in `package.json`.

## Build and Start

Run from the repository root:

```sh
pnpm install --frozen-lockfile
pnpm build
pnpm start
```

The default address is [http://127.0.0.1:3000](http://127.0.0.1:3000). `server/main.ts` executes directly in Node using erasable TypeScript; no TypeScript loader or Vite process is used in production.

Keep `dist/`, `server/`, `shared/`, `package.json`, and `pnpm-lock.yaml` together. Node imports the shared application schemas at runtime. When deploying an already-built frontend, install only runtime dependencies with `pnpm install --prod --frozen-lockfile`, then run `pnpm start`. Building on the host requires development dependencies.

Rebuild and restart the service when deploying changes. Static-file lookup is initialized at startup, so replacing `dist/` under a running process is insufficient.

## Configuration

Use [.env.example](../.env.example) as the template. `pnpm start` reads an optional `.env` file; existing process environment variables take precedence.

| Variable               | Evaluated      | Default          | Purpose                                 |
| ---------------------- | -------------- | ---------------- | --------------------------------------- |
| `HOST`                 | Server startup | `0.0.0.0`        | Listen address                          |
| `PORT`                 | Server startup | `3000`           | Listen port, an integer from 1 to 65535 |
| `VITE_CLIENT_API_BASE` | Frontend build | `/client-api/v1` | Normalized application API base         |
| `VITE_MEDIA_BASE`      | Frontend build | `/media`         | Media proxy endpoint                    |

Keep the default relative frontend routes for a single-origin deployment. Changing a `VITE_*` value requires rebuilding; changing `HOST` or `PORT` requires restarting. Frontend endpoint overrides do not change the server's upstream allowlist.

`VITE_API_BASE` previously selected the raw upstream-shaped API and is deprecated for frontend builds. Default deployments need only the updated `.env.example`. A custom legacy value without an explicit `VITE_CLIENT_API_BASE` produces a build diagnostic. Point the new variable to a service implementing the normalized client routes; changing only the variable name does not convert a raw proxy into that service. Existing raw `/api` proxy clients retain their route contract.

## Routes and Hosting

| Route                               | Behaviour                                                        |
| ----------------------------------- | ---------------------------------------------------------------- |
| `/`, `/programmes/:id`, `/settings` | Built frontend with Vue Router history fallback                  |
| `/assets/*`                         | Hashed assets with immutable caching                             |
| `/api/app/v1/programs...`           | Restricted programme metadata proxy                              |
| `/client-api/v1/*`                  | Normalized programme data and POST playback/download preparation |
| `/media?url=...`                    | MP4 preview or attachment streaming                              |
| `/healthz`                          | Local readiness response: `{"status":"ok"}`                      |

The service serves only `dist/`. HTML revalidates with ETags. Missing assets, reserved proxy paths, and dotfiles do not receive the SPA fallback. Static files ignore Range headers; Range support belongs to the media proxy.

The health route does not contact upstream services, so it confirms the app service is running, not upstream availability.

Use a host that permits long-lived Node processes, outbound HTTPS, streaming responses, and large transfers. Any HTTPS gateway or reverse proxy must preserve Range and If-Range requests, partial-response headers, and long download connections. Media consumes the host's outgoing bandwidth; the app server does not store downloaded videos.

Static hosting such as GitHub Pages alone cannot supply the Referer required by the tested video CDN. It can host the frontend only if a separate compatible media service is provided. See [Upstream API](upstream-api.md) for the recorded restriction and proxy contract.

## Operations

Startup fails when `dist/index.html` is missing or the port is invalid. SIGINT and SIGTERM stop accepting new requests and give active transfers up to 30 seconds before closing connections.

Client API and proxy boundaries report server failures to stderr with the request method, route pathname, and original error cause. Caller query values are omitted from the diagnostic label. Invalid input, missing records, and client disconnects do not produce failure diagnostics.

For deployment verification, check `/healthz`, open a programme route directly, load programme metadata, and test media with HEAD or a small Range request. A complete episode download is unnecessary.

| Symptom                               | Check                                                               |
| ------------------------------------- | ------------------------------------------------------------------- |
| Missing frontend build                | Run `pnpm build` before starting; include `dist/` in the deployment |
| Port already in use                   | Choose a free `PORT` and restart                                    |
| Programme requests return HTML        | Check frontend endpoint settings and proxy routing                  |
| Media returns 400                     | Check the encoded URL against the media allowlist                   |
| Media returns 403 or 502              | Check upstream accessibility and the required Referer               |
| New assets return 404 after an update | Restart the service after replacing the build                       |

`pnpm preview` is for local build verification at port 4173. It is not the production entry point.
