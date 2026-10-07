# Upstream API and Proxy Contracts

This is the contract used by the current implementation, not an official upstream API specification. Frontend validation lives in `src/features/programmes/schemas.ts`; requests in `api.ts`; proxy policy in `server/proxy.ts` and `server/media.ts`.

## Programme Endpoints

The upstream origin is `https://gw.scgchc.com`. The default browser-facing base is `/api`.

| Method | Upstream path                                                 | Response data                         |
| ------ | ------------------------------------------------------------- | ------------------------------------- |
| GET    | `/app/v1/programs?page=0&size=100`                            | Catalogue object containing `records` |
| GET    | `/app/v1/programs/{programmeId}/dates/list`                   | Broadcast date array                  |
| GET    | `/app/v1/programs/{programmeId}/dates/{dateId}/contents/list` | Content array for one broadcast       |

A successful JSON envelope has `rs: 200` and `data`. Other business status values use the envelope's `error` message; non-JSON, invalid shapes, and HTTP errors produce localized client errors.

`dateId` is the returned date record ID, not its ISO date text. Keep all domain IDs as strings. The boundary accepts safe integer IDs and normalizes them to strings, but rejects numeric IDs above the safe integer range.

The date client deduplicates ISO calendar dates, keeps the last upstream record for each date, and sorts newest first. The catalogue currently requests only page 0 with size 100; the proxy fixes those values rather than forwarding arbitrary pagination parameters.

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

A browser cannot use [Fetch's referrer option](https://developer.mozilla.org/en-US/docs/Web/API/RequestInit#referrer) to assign an arbitrary foreign-origin Referer. The media proxy supplies the required player origin.

## Proxy Contracts

`/api` accepts only the three programme path shapes above. It forwards GET or HEAD, requests JSON, and rejects unsupported paths. Redirects are not followed.

`/media` accepts an encoded `url` query parameter targeting an HTTPS MP4 on `fscgc.scgchc.com`. Credentials, nondefault ports, other hosts/protocols, and non-MP4 paths are rejected. Redirects are rejected rather than followed.

For preview, use `/media?url=<encoded-upstream-url>`. For browser download, add `download=1` and `filename=<encoded-filename>`; the response supplies a sanitized RFC 5987 Content-Disposition attachment filename. `src/shared/media.ts` builds these query parameters with `URLSearchParams`.

The media proxy:

- Adds `Referer: https://scgc.video.play/`.
- Forwards Range and If-Range, preserves successful upstream status, and copies relevant media/partial-response headers.
- Requests identity encoding and avoids copying an encoded body's obsolete Content-Length.
- Streams with native backpressure and aborts upstream work when the client disconnects.
- Handles HEAD without a response body and returns upstream HTTP errors or a 502 for connection failures.

An alternate media endpoint must support HEAD and return an attachment response with a video or octet-stream content type. See [Architecture](architecture.md) for the browser download flow.
