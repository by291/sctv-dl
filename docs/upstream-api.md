# Upstream API and Proxy Contracts

This is the contract used by the current implementation, not an official upstream API specification. Upstream validation and normalization live in `server/programmes/`; application DTO schemas live in `shared/contracts/`; proxy policy lives in `server/proxy/proxy-policy.ts` and media transport in `stream-upstream.ts`.

## Programme Endpoints

The upstream origin is `https://gw.scgchc.com`. The raw proxy base is `/api`; the current frontend uses the normalized client API described below.

| Method | Upstream path                                                 | Response data                         |
| ------ | ------------------------------------------------------------- | ------------------------------------- |
| GET    | `/app/v1/programs?page=0&size=100`                            | Catalogue object containing `records` |
| GET    | `/app/v1/programs/{programmeId}/dates/list`                   | Broadcast date array                  |
| GET    | `/app/v1/programs/{programmeId}/dates/{dateId}/contents/list` | Content array for one broadcast       |

A successful JSON envelope has `rs: 200` and `data`. Other business status values use the envelope's `error` message; non-JSON, invalid shapes, and HTTP errors produce localized client errors.

`dateId` is the returned date record ID, not its ISO date text. Keep all domain IDs as strings. The boundary accepts safe integer IDs and normalizes them to strings, but rejects numeric IDs above the safe integer range.

The date client deduplicates ISO calendar dates, keeps the last upstream record for each date, and sorts newest first. The catalogue currently requests only page 0 with size 100; the proxy fixes those values rather than forwarding arbitrary pagination parameters.

## Android Guest Request Profile

The native programme client and the Web metadata proxy reproduce the anonymous request headers inspected in the **9.6.1.5 APK**. These are compatibility values for upstream requests, separate from this project's product version. Both clients send:

| Header                                        | Value                                                                                        |
| --------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `userId`, `Authorization`, `captchaId`        | Empty strings, matching the official guest state                                             |
| `deviceId`                                    | Persistent random UUID for the installation or browser                                       |
| `deviceBrand`, `deviceModel`, `systemVersion` | Native Android `Build` values; the Web proxy simulates `google`, `Pixel 8`, and Android `14` |
| `deviceType`                                  | `android`                                                                                    |
| `appVersion`                                  | `9.6.1.5`                                                                                    |
| `User-Agent`                                  | `okhttp/4.12.0`                                                                              |
| `Accept-Encoding`                             | `gzip`                                                                                       |

Android stores its UUID in the `upstream_client` shared preferences, outside the settings-only backup allowlist. First requests serialize identity creation so concurrent calls retain one persisted value. The interceptor belongs only to the programme API client; covers, media probes, playback, and system downloads do not receive these business headers.

The raw Web proxy uses an HTTP-only `sctv-dl-device-id` cookie scoped to `/api`, with `SameSite=Lax` and a one-year lifetime. The normalized client API uses the same cookie name scoped to `/client-api`, retaining one identity across its requests and reusing it for all upstream calls within a preparation operation. The two scopes are independent: upgrading from the raw frontend establishes the new scoped identity once, while preserving browser settings/favourites and the raw proxy cookie contract. A missing or invalid UUID causes a new one to be issued. Browser cookies must be enabled to retain the identity, and clearing the cookie creates a new simulated installation. The proxy uses only this validated UUID; it does not forward browser cookies, authorization, or device headers upstream. It also retains `Accept: application/json`. These headers apply to the project's raw proxy and normalized client service. Custom normalized API deployments own the equivalent transport contract; see [Deployment](deployment.md) for the API-base migration.

All three programme requests remain GET requests without a body or additional signature parameters. Host and connection management remain with the HTTP transport. Media keeps its separate Referer and Range contract below.

## Field Mapping

| Record    | Upstream field         | Application field / meaning              |
| --------- | ---------------------- | ---------------------------------------- |
| Programme | `id`, `name`, `cover`  | String ID, name, nullable cover URL      |
| Date      | `id`, `date`           | String date ID, ISO calendar date        |
| Content   | `id`, `title`, `cover` | String ID, title, nullable cover URL     |
| Content   | `video`                | `video`: standard variant                |
| Content   | `videoStandard`        | `smoothVideo`: smooth variant            |
| Content   | `pubTime`              | `publishedAt`: nullable publication text |

The upstream naming is counterintuitive: `videoStandard` is the smooth variant in this client. Do not infer quality from the field name.

Missing optional video and cover fields normalize to `null`. Relative media paths resolve against `https://fscgc.scgchc.com/`; relative image paths use `https://kscgc.sctv.com/`. URL normalization does not grant permission to proxy a host: media targets still pass the server allowlist.

`resolveVideo` falls back to an available variant. `getVideoVariants` omits duplicate URLs so the player exposes only distinct choices.

## Browser Access: Recorded Observations

Verification on **2026-10-06** recorded:

- Programme metadata responses supplied `Access-Control-Allow-Origin: *`.
- A tested MP4 returned HTTP 403 without a Referer and HTTP 200 with `Referer: https://scgc.video.play/`.

These are dated observations, not a guarantee for every current response. Recheck them when troubleshooting upstream behaviour. The default deployment proxies metadata as well as media for one consistent origin.

Verification on **2026-10-16** of the 2021-02-05 音你而来 video on `fscgc.sctv-tf.com` also found that HEAD requests without a User-Agent returned 403, while the application's `sctv-dl/<package-version>` identifier returned 200 with the same media Referer. Native playback and download clients therefore send that identifier explicitly.

A browser cannot use [Fetch's referrer option](https://developer.mozilla.org/en-US/docs/Web/API/RequestInit#referrer) to assign an arbitrary foreign-origin Referer. The media proxy supplies the required player origin.

## Proxy Contracts

`/api` accepts only the three programme path shapes above. It forwards GET or HEAD, requests JSON, and rejects unsupported paths. Redirects are not followed.

`/media` accepts an encoded `url` query parameter targeting an HTTPS MP4 on `fscgc.scgchc.com` or `fscgc.sctv-tf.com`. The latter also serves historical programme videos, including the 2021-02-05 broadcast of 音你而来. Credentials, nondefault ports, other hosts/protocols, and non-MP4 paths are rejected. Redirects are rejected rather than followed. The Web preparation service and native playback/download services enforce the same allowlist, covered by `shared/fixtures/media-policy.json`.

For preview, use `/media?url=<encoded-upstream-url>`. For browser download, add `download=1` and `filename=<encoded-filename>`; the response supplies a sanitized RFC 5987 Content-Disposition attachment filename. `src/shared/media/media-proxy-url.ts` builds these query parameters with `URLSearchParams`.

The media proxy:

- Adds `Referer: https://scgc.video.play/`.
- Forwards Range and If-Range, preserves successful upstream status, and copies relevant media/partial-response headers.
- Requests identity encoding and avoids copying an encoded body's obsolete Content-Length.
- Streams with native backpressure and aborts upstream work when the client disconnects.
- Handles HEAD without a response body and returns upstream HTTP errors or a 502 for connection failures.

An alternate media endpoint must support HEAD and return an attachment response with a video or octet-stream content type. See [Architecture](architecture.md) for the browser download flow.

## Normalized Client API

The frontend's default base is `/client-api/v1`, overridden at build time by `VITE_CLIENT_API_BASE`. Successful responses are `{ data: T }`; failures are `{ error: { code, message } }`. Application DTO IDs are strings, including values above the JavaScript safe integer boundary. Upstream numeric IDs above that boundary remain invalid.

| Method     | Path relative to base                               | Result                                                       |
| ---------- | --------------------------------------------------- | ------------------------------------------------------------ |
| GET / HEAD | `/programmes`                                       | Normalized programme array                                   |
| GET / HEAD | `/programmes/{programmeId}/dates`                   | Deduplicated dates, newest first                             |
| GET / HEAD | `/programmes/{programmeId}/dates/{dateId}/contents` | Normalized content array                                     |
| POST       | `/playback/prepare`                                 | Session ID, selected quality, distinct validated source URLs |
| POST       | `/downloads/prepare`                                | Prepared files, per-file failures, fallback indicator        |

Playback input is `{ programmeId, dateId, contentId, quality }`; download input is `{ programmeId, dateId, contentIds, quality }`. JSON bodies are limited to 16 KiB and batches to 100 distinct content IDs. Invalid or extra request fields are rejected. Neither route accepts caller-supplied media URLs, filenames, or filesystem paths. Preparation resolves the date and contents against upstream records; filenames and actual quality come from the backend.

Normalized metadata and preparation requests use a separate 20-second response-header deadline for each upstream request. Incoming preparation bodies have their own 20-second reception limit. Disconnecting the client cancels active upstream work. Sequential successful requests do not share a whole-operation timeout, and a received response body is not cut off merely because 20 seconds have elapsed since the operation began.

Invalid input returns 400, missing records/routes 404, unsupported methods 405, upstream failure 502, timeout 504, and unexpected server failure 500. Client API errors never fall through to frontend HTML. Preparation returns HTTP 200 when individual files fail but the batch itself can be evaluated; inspect `failures` alongside `files`.

Web playback adapters wrap the validated source URLs with the existing media proxy. Web playback preparation owns no server-side session resource, so closing that adapter does not make another HTTP request. The current preview component retains its existing direct media-proxy integration until the native playback-session phase.
