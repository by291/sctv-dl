# Shared Web and Tauri Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Windows and macOS Tauri applications and the existing website from one Vue frontend, with native desktop services owning upstream integration, playback transport, downloads, and persistence.

**Architecture:** Introduce typed application ports and select Web or Tauri adapters once at startup. Serve normalized Web DTOs from Node while Rust exposes equivalent Tauri commands. Bundle static frontend assets normally; select the desktop media transport through an explicit two-platform validation gate.

**Tech Stack:** Vue, TypeScript, Vite, Pinia, Naive UI, VueUse, Zod, Artplayer, Node native HTTP/fetch, Tauri 2, Rust, Tokio, reqwest, official Tauri Dialog/Store plugins; Axum only if required by the media validation gate.

**Spec:** [Shared Web and Tauri Desktop Design](../specs/2026-10-16-tauri-desktop-design.md). The user authorized the initial implementation batch after the planning commit; the remaining tasks describe the complete delivery scope.

## Execution Status — 2026-10-16

Planning was committed as `bb36aa1`. The initial implementation is on `feat/tauri-foundation`, grouped into commits for shared contracts/ports, normalized Node/Web services, the Tauri shell, and phase documentation.

| Task | Status   | Evidence and remaining work                                                                                                                                                       |
| ---- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Partial  | Standard Tauri shell builds and launches on macOS with bundled assets and no Node server. Native media investigation, transport selection, and Windows validation remain pending. |
| 2    | Complete | Shared schemas, fixtures, injectable ports, and dependency boundaries are implemented and tested.                                                                                 |
| 3    | Complete | Normalized Node routes and Web adapters are integrated; browser behaviour, production, and preview were checked.                                                                  |
| 4–9  | Pending  | Native services, playback, downloads, settings integration, full UI acceptance, and distribution work have not started.                                                           |

Tasks 2 and 3 proceeded while the two-platform media gate remains open because they do not select or depend on the native playback transport. Task 5 must still wait for that gate. The packaged application currently renders the interface but cannot load programme data through native services.

Validation: `pnpm check` passes with 205 tests in 34 files; `pnpm build`, Rust formatting, Clippy, Cargo scaffold checks, and a local macOS application bundle pass. Cargo currently contains zero native business tests. Browser checks covered desktop/narrow layouts and themes. Production and built-preview APIs returned the real catalogue; the existing Web media proxy returned HEAD 200 and Range 206 for a 1,024-byte probe. See [desktop development](../../desktop.md) and [validation evidence](../../desktop-media-validation.md) for limitations.

Implementation details: retain `programme-api.ts` as the Web adapter's existing public module path; isolate the normalized route's guest cookie under `/client-api` while retaining the raw `/api` cookie scope. Playback UI integration and settings-store hydration remain assigned to Tasks 5 and 7 respectively.

## Global Constraints

- Proposed first-release matrix: Windows 10/11 x64; macOS 13 or newer on Apple Silicon and Intel. This is a product target, not a statement of Tauri's minimum requirements. Test the lowest supported OS versions before claiming support.
- Node.js remains `>=24.15.0`; pnpm remains `12.9.1` unless an independently justified dependency change is requested.
- Use Tauri 2 and existing Vue, Pinia, Naive UI, VueUse, Zod, and Artplayer. Prefer official Tauri Dialog and Store plugins, accessed from Rust for desktop operations.
- Use Rust `reqwest` and Tokio for native HTTP, cancellation, and asynchronous file writes. Do not add a generic plugin system, custom IPC framework, monorepo package manager, or a Node sidecar.
- All domain IDs are decimal strings. Reject upstream numeric IDs above `9007199254740991`; retain larger IDs only when supplied as strings.
- `video` means standard quality; upstream `videoStandard` means smooth quality. Preserve fallback behaviour and omit duplicate playback URLs.
- Metadata headers follow the current anonymous Android guest profile, including one persistent desktop installation UUID. Never send those headers to covers or media.
- Media targets remain HTTPS MP4 files on `fscgc.scgchc.com`, without credentials or nondefault ports. Add `Referer: https://scgc.video.play/`; reject redirects.
- Preserve request cancellation, stale-response guards, browser storage compatibility, truthful browser handoff, and player cleanup after the modal leave animation.
- Keep metadata's 20-second response-header deadline, and use a 30-second idle-read deadline for native bodies and transfers. A long, actively progressing MP4 must not hit a whole-file timeout.
- Preparation POST bodies are JSON with a 16 KiB limit and at most 100 distinct content IDs.
- Run at most two transfers concurrently. Emit progress at most every 100 ms per task, with every terminal update delivered immediately. Unknown totals remain `null`; never manufacture a percentage.
- Pause/resume, restart recovery, automatic updates, tray residency, account synchronization, Linux packages, and store submission are follow-up work.
- Documentation, comments, tests, and commit messages use English. Product copy and upstream names remain Chinese.
- Do not modify Android behaviour. Commit, push, publish, or deploy only when requested.

## Review Focus

- A delayed open/request resolves after cancellation or reopening: release obsolete native resources and keep the newest page/player state. Tests belong to Tasks 4 and 5.
- A destination already exists or differs only by case on Windows/macOS: preserve it and reserve a distinct filename even under concurrent transfers. Tests belong to Task 6.
- Storage hydration or an older asynchronous save finishes after a newer edit: keep the newest setting and display storage failures. Tests belong to Task 7.
- Native task events arrive before or during the initial snapshot: merge by per-task revision without losing a terminal event. Tests belong to Task 6.
- A development window works but an installed build has another origin/protocol: verify real playback, routing, CSP, directory access, and menus in installed applications. Tests belong to Tasks 1, 5, and 9.

## Scope and Deliverables

The deliverables are one shared UI; equivalent normalized programme services; native preview and batch downloads; persistent desktop settings; a desktop task panel; Windows/macOS build jobs; release configuration; and operation/validation documentation. Existing Web browsing, browser-managed downloads, and production deployment remain supported.

The user-visible desktop additions are a directory picker, actual transfer state/progress, cancel/retry actions, and confirmation before exiting with active work. Keep the existing three-page navigation; place the task panel in the application shell rather than introduce a second programme UI.

Public release signing is a separate acceptance dimension from application functionality. Prepare configuration and document required credentials; do not create certificates, spend money, upload artifacts publicly, or start a release without a user request.

## File Structure and Responsibilities

Paths below are planned additions or modifications. They do not exist merely because this plan names them. Keep tests beside their owners; Rust integration tests live in `src-tauri/tests/`.

| Paths                                                                                                     | Responsibility                                                                                     |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `shared/contracts/{programmes,media,downloads,settings,errors}.ts`                                        | Platform-neutral Zod DTO schemas, inferred types, normalized errors                                |
| `shared/fixtures/{programmes,media-policy,download-names,settings}.json`                                  | Equivalent Node/Rust contract examples and edge cases                                              |
| `src/shared/platform/ports.ts`, `usePlatform.ts`                                                          | Port interfaces, injection key, and typed access; no feature imports                               |
| `src/platform/{create-platform,web-platform,tauri-platform}.ts`                                           | Environment detection, lazy native loading, application composition                                |
| `src/features/programmes/api/programme-api.{web,tauri}.ts`                                                | Equivalent normalized catalogue/date/content adapters                                              |
| `src/features/programmes/api/playback.{web,tauri}.ts`                                                     | Playback session control; Web proxy URL adaptation                                                 |
| `src/features/programmes/api/downloads.{web,tauri}.ts`                                                    | Browser handoff or native task bridge                                                              |
| `src/features/settings/api/settings.{web,tauri}.ts`                                                       | Storage adapter, Web cross-tab synchronization, Rust-backed desktop persistence                    |
| `src/features/downloads/stores/useDownloadTasksStore.ts`                                                  | Shared presentation state for native tasks                                                         |
| `src/features/downloads/components/DownloadTasksPanel.vue`                                                | Native task progress, cancel, retry, and failure feedback                                          |
| Existing programme composables, stores, and preview components                                            | Consume injected ports; preserve page and player lifecycles                                        |
| `server/client-api/{client-api-middleware,programme-service}.ts`                                          | Normalized HTTP routes and request-scoped orchestration                                            |
| `server/programmes/{programme-client,upstream-schemas,upstream-urls,video-variants,download-file}.ts`     | Upstream transport, normalization, quality, and filename rules moved from browser business modules |
| `src-tauri/{Cargo.toml,Cargo.lock,build.rs,tauri.conf.json}`                                              | Standard native application definition and build configuration                                     |
| `src-tauri/{capabilities/default.json,permissions/app.toml,icons/}`                                       | Main-window permissions, custom-command allowlist, and application icons                           |
| `src-tauri/src/{main,lib,commands,state,requests,error}.rs`                                               | Application composition, thin command handlers, state and cancellation                             |
| `src-tauri/src/programmes/{mod,client,models}.rs`                                                         | Rust programme service, upstream normalization, stable installation profile                        |
| `src-tauri/src/media/{mod,policy,protocol}.rs`                                                            | Opaque playback sessions, validation, selected custom-protocol transport                           |
| `src-tauri/src/media/http.rs`                                                                             | Conditional replacement transport if the custom protocol fails the gate                            |
| `src-tauri/src/downloads/{mod,manager,files}.rs`                                                          | Native queue, task states, transfer lifecycle, collision-safe file finalization                    |
| `src-tauri/src/settings.rs`                                                                               | Rust-owned preferences, installation UUID, and selected directory                                  |
| `src-tauri/tests/{programme_api,media,downloads,settings}.rs`                                             | HTTP stubs, temporary directories, integration regressions                                         |
| `package.json`, `pnpm-lock.yaml`, Vite/Vitest/TypeScript/ESLint configuration                             | Scripts, aliases, build targets, and dependency-boundary checks                                    |
| `server/http-app.ts`, `tooling/upstream-proxy-plugin.ts`                                                  | Integrate normalized routes in production, development, and preview                                |
| `.gitignore`, `.prettierignore`, `.github/workflows/desktop.yml`, `.github/workflows/desktop-release.yml` | Native artifacts, checks, and manually triggered distribution                                      |
| `docs/desktop.md`, `docs/desktop-media-validation.md`, existing owning docs                               | Desktop operation and evidence; durable contracts and handoff                                      |

Keep `src/shared/media/browser-download.ts` as the browser handoff implementation. Move upstream-only schemas, URL normalization, quality resolution for transfers, and naming coverage into the server-owned files above. Preserve frontend helpers that still implement presentation, such as full-episode matching and formatting. Delete unused former modules only after their callers and meaningful tests have migrated.

## Dependency Order and Checkpoints

```text
1. Baseline, native shell, and disposable media investigation
2. Shared DTOs and injectable platform ports
3. Normalized Node services and Web adapters
4. Native programme services and cancellation
5. Production playback transport and lifecycle integration
6. Native download manager and shared task presentation
7. Persistent settings and native application lifecycle
8. Shared UI, routing, styling, and browser regressions
9. Native CI, installed-app acceptance, and release handoff
```

Execute in this order for the initial implementation. Tasks 2–4 establish interfaces used by later tasks. The media investigation is a risk-reduction checkpoint, not a claim of production-ready playback. If Windows interactive validation is unavailable, record that explicitly and do not mark the two-platform media gate passed.

### Task 1: Establish the Native Shell and Media Feasibility Evidence

**Files:** Create the standard `src-tauri/` application files, `src-tauri/icons/`, and `docs/desktop-media-validation.md`; modify `package.json`, `pnpm-lock.yaml`, `vite.config.ts`, `.gitignore`, and `.prettierignore`. Use a temporary untracked media harness; remove it after recording results.

**Interfaces:** Produces `pnpm tauri dev`, `pnpm tauri build`, a main window loading bundled assets in release mode, and the spec's custom-protocol versus media-only HTTP transport decision. No new application business command is consumed by later tasks from this disposable harness.

- [x] Record `git status --short --branch`, available Rust/native build prerequisites, and the installed Node/pnpm versions. Preserve the existing ahead commit and any unrelated work. Run the existing `pnpm check` and `pnpm build` as the implementation baseline; label pre-existing failures separately.
- [x] Initialize Tauri 2 against the current Vue/Vite root, using the official integration instructions. Resolve compatible versions at execution time, commit lockfiles only when committing is requested, and record the tested Rust compiler and dependency MSRV. Configure `frontendDist: ../dist`, development port `5180`, strict port handling, and native build-output ignores.
- [x] Add scripts `tauri: tauri`, `desktop:dev: tauri dev`, and `desktop:build: tauri build`. Preserve every existing Web command. Add WebView-compatible Vite targets for the proposed minimum systems and ignore `src-tauri/` in frontend file watching and dependency discovery.
- [x] Build and launch a release-mode application to prove bundled HTML/assets load without Node. Record native origin, route behaviour, and CSP requirements; this is a shell check, not full product acceptance.
- [ ] Exercise a disposable Rust media harness using a deterministic HTTP stub first. Check HEAD, `bytes=0-1023`, open-ended ranges, suffix ranges, 416, an initial no-Range request, and response buffering bounded to 1 MiB. Confirm Referer insertion, redirect rejection, and cancellation.
- [ ] Run initial playback, forward/backward seek, variant switching, and close/reopen on actual Windows WebView2 and macOS WKWebView. Sample live upstream access with HEAD or a small Range request; any longer playback is a deliberate interactive check, not a bulk media download. Observe memory on a large fixture rather than infer bounded memory from source alone.
- [ ] Apply the spec's decision rule. If custom-protocol requirements fail, validate the media-only loopback endpoint under the same cases and record why it is needed. Record exact OS/WebView versions, chosen transport, measured observations, and missing coverage in `docs/desktop-media-validation.md`. Remove the disposable harness.

**Verification:** Existing Web checks pass; `pnpm tauri build --no-bundle` builds the host application; a packaged application loads without the development server. The media gate requires interactive evidence on both platforms. Do not quietly substitute a local browser for either native WebView.

**Checkpoint:** Review the transport result before implementing Task 5. If no bounded streaming approach passes both targets, stop the affected playback work with evidence and revise the proposal before promising support.

### Task 2: Define DTOs and Injectable Platform Ports

**Files:** Create `shared/contracts/*.ts`, `shared/fixtures/*.json`, colocated contract tests, and `src/shared/platform/{ports,usePlatform}.ts`. Modify `tsconfig.app.json`, `tsconfig.node.json`, `vite.config.ts`, `vitest.config.ts`, `eslint.config.js`, and `tooling/module-boundaries.test.js`. Concrete platform composition lands in Tasks 3 and 7, after the corresponding adapters exist.

**Interfaces:** Consume the exact DTOs and ports from the spec. Produce `platformKey: InjectionKey<AppPlatform>` and `usePlatform(): AppPlatform`. Define `AppPlatform.dispose(): Promise<void>` for adapter listener/scope cleanup. `NativeDownloadPort` has `kind: 'native'`; browser downloads have `kind: 'browser'`, allowing type-safe capability narrowing.

- [x] Add failing contract tests: normalized IDs accept `'9007199254740992'` but reject the numeric value; fixture expectations distinguish `video` from `smoothVideo`; normalized optional URLs accept `null`; malformed DTOs do not reach UI state. Upstream normalization itself is tested in Tasks 3 and 4. Add boundary tests forbidding `shared/contracts/` from importing `src/` or `server/`.
- [x] Add failing injection tests: supplied ports are returned unchanged; missing platform injection throws an explicit developer error. Add dependency-boundary tests preventing feature code from importing `src/platform/` composition and components from importing Tauri APIs. Run the focused tests and verify failure identifies the absent contracts/boundaries rather than an unrelated runner error.
- [x] Implement the schemas and inferred types. Use existing normalized content fields; do not duplicate application models in every adapter. Add `@shared/* -> shared/*` to browser/test resolution and include shared sources in both TypeScript projects. Node imports retain explicit `.ts` extensions.
- [x] Define ports in shared code without feature imports. Keep existing runtime consumers intact until Task 3 wires the complete Web implementation; do not introduce placeholder native services to make this task compile. Keep library/selection/presentation state owned by Vue/Pinia.
- [x] Run `pnpm test shared/contracts src/shared/platform tooling/module-boundaries.test.js`, then `pnpm typecheck` and `pnpm lint`. All DTO, injection, and dependency-boundary tests pass.

**Checkpoint:** Both targets have one typed application interface available for injection. Current startup still works, no component imports a Tauri module, and shared modules still import no feature modules.

### Task 3: Preserve Web Behaviour Through Normalized Node Services

**Files:** Create the listed `server/client-api/` and `server/programmes/` files and colocated tests; create `programme-api.web.ts`, `playback.web.ts`, `downloads.web.ts`, `settings.web.ts`, and `src/platform/web-platform.ts` with colocated tests. Modify `src/main.ts`, `server/http-app.ts`, `server/http-app.test.ts`, `tooling/upstream-proxy-plugin.ts`, `.env.example`, Vite configuration and its tests, programme consumers, and media handoff helpers as needed. Move/remove browser upstream-only modules after replacement coverage exists.

**Interfaces:** Produce the five `/client-api/v1` routes in the spec and Web implementations of `ProgrammeApi`, `PlaybackPort`, browser `DownloadPort`, and `SettingsPort`. Produce `createWebPlatform(): AppPlatform`. Export `clientApiMiddleware(request: IncomingMessage, response: ServerResponse, next: () => void): void` for production and Vite. Add `VITE_CLIENT_API_BASE`, preserve `VITE_MEDIA_BASE`, and implement the spec's explicit migration diagnostic for custom legacy `VITE_API_BASE` values. Raw `/api` remains available with its previous contract.

- [x] Add failing server tests for valid/invalid route IDs, business errors, non-JSON responses, safe integer enforcement, date deduplication, descending dates, omitted variants, and 16 KiB/100-ID preparation limits. Confirm duplicate IDs are deduplicated and an oversized batch is rejected before upstream work.
- [x] Add failing HTTP integration tests proving POST preparation reaches its handler before static method filtering, unsupported methods return 405, unknown client routes return API errors rather than SPA HTML, HEAD carries no body, and `/healthz`, assets, raw `/api`, and `/media` retain their contracts. Add configuration tests for default endpoints, the new override, and the diagnostic for an unmigrated custom legacy API base.
- [x] Extract the existing normalization and naming logic into server-owned services with shared DTO outputs. Create one request-scoped metadata-header context per incoming client operation so all upstream calls in the same preparation use the same installation identity, including the first cookie-setting request.
- [x] Implement the normalized routes and common error envelopes. Resolve preparation content references on the backend; do not accept caller-supplied media URLs or filenames. Reuse one date/content resolution per batch, preserving per-file failures and actual-quality filenames.
- [x] Wire the same middleware into Vite development, Vite preview, and production. Abort upstream work on disconnect and preserve manual redirect handling and existing proxy allowlists. Update the production SPA exclusions for `/client-api/`.
- [x] Implement Web adapters. Validate DTO responses with Zod; propagate `AbortSignal`; convert returned source URLs through `proxyMediaUrl`. Keep browser HEAD/attachment/content-type preflight and temporary-anchor handoff. Return `kind: 'browser'` with the actual handoff count, fallback flag, and per-file failures.
- [x] Wrap existing VueUse persistence as the Web settings adapter, compose complete Web ports, and provide them from startup. Migrate programme consumers from the API singleton to injected ports; retain optional explicit `ProgrammeApi` injection in `useProgrammeArchive`. Test that Web composition invokes no native API and disposes its listeners/scopes. Native startup selection is activated only in Task 7, after all native adapters exist.
- [x] Add/retain browser regressions for mixed batches, a failed first file followed by a successful second file, unsupported media targets, and cancelled preparation. Assert that a handoff never creates a completed task or a fabricated progress percentage.
- [x] Run `pnpm test server src/features/programmes/api src/shared/media`, then `pnpm check` and `pnpm build`. Run local production and preview smoke checks for the normalized routes using an upstream stub; stop temporary processes afterward.

**Checkpoint:** The website still offers all current flows with the same visible download promises, while the frontend consumes normalized application data instead of interpreting upstream envelopes.

### Task 4: Implement Rust Programme Services and Explicit Cancellation

**Files:** Create `src-tauri/src/{commands,state,requests,error,settings}.rs`, `src-tauri/src/programmes/{mod,client,models}.rs`, `src-tauri/tests/programme_api.rs`, and `programme-api.tauri.ts` with tests. Modify `lib.rs`, Cargo dependencies, capabilities, and custom-command permissions. This task establishes the small native Store-backed installation-identity service; Task 7 extends it with user preferences.

**Interfaces:** Expose `list_programmes(requestId)`, `list_programme_dates(programmeId, requestId)`, `list_programme_contents(programmeId, dateId, requestId)`, and `cancel_request(requestId)`. Rust payload structs use serde camelCase to match TypeScript. Produce a native `ProgrammeApi` preserving the existing `AbortSignal` signatures and normalized DTOs.

- [ ] Write failing Rust integration tests against a disposable HTTP stub: normalize the same shared fixtures as Node; reject invalid IDs and redirects; preserve business errors; sort/deduplicate dates; send the existing guest profile to metadata only. Concurrent first requests must share one persisted UUID.
- [ ] Write failing cancellation tests for an already-aborted signal, abort during response headers/body, cancellation before registry insertion, normal completion, and a late response after a programme/date switch. Assert no active entry remains after any terminal path and stale results never commit to view state.
- [ ] Implement `ProgrammeService` with a reusable reqwest client and injected test upstream origin. Production origins are fixed, not command parameters. Validate external records and JSON numeric IDs before normalization. Preserve the spec's response-header and idle deadlines. Initialize the Store-backed installation UUID before exposing metadata commands and serialize its first creation.
- [ ] Implement `RequestRegistry`: register UUID requests, propagate cancellation to native futures, and clean up after completion/error. Bound early-cancellation markers to 1,024 entries with a 60-second expiry; test expiry and capacity without real sleeps using injected time.
- [ ] Implement thin commands around the service and registry. Restrict available custom commands to the local main window using Tauri's application command manifest/permissions; validate inputs inside commands as well. Avoid a broad frontend HTTP or filesystem permission grant.
- [ ] Implement the TypeScript abort bridge with listener cleanup and adapter-boundary DTO validation. Preserve `LatestRequest` independently of cancellation. Ignore only expected cancellation errors; preserve real failures for user feedback.
- [ ] Run `cargo test --manifest-path src-tauri/Cargo.toml --test programme_api` and focused TypeScript adapter/archive tests. Both languages must consume the same raw/expected fixture cases and produce equivalent application DTOs.

**Checkpoint:** Exercise catalogue/date/content commands and the native adapter in the native shell with Node stopped, including deliberately slow/cancelled requests. Full shared-application native startup is connected in Task 7; do not claim that integration from command tests alone.

### Task 5: Integrate Production Playback Sessions

**Files:** Create `src-tauri/src/media/{mod,policy,protocol}.rs` or the selected `http.rs`, `src-tauri/tests/media.rs`, and `playback.tauri.ts` with tests. Modify `commands.rs`, `state.rs`, `tauri.conf.json`, `ProgrammePreviewDialog.vue`, `ProgrammeVideoPlayer.vue`, their tests, and the archive's preview context.

**Interfaces:** Expose `open_playback(request: PlaybackRequest, requestId): PlaybackSession` and `close_playback(sessionId): void`. Produce `PlaybackPort`. Add `ContentRef` context to preview opening so the backend resolves source identity rather than accepting an arbitrary URL. Preserve the existing Artplayer component API for display/control wherever possible.

- [ ] Write failing media-policy tests from the shared fixtures: permitted CDN MP4, forbidden host/protocol/credentials/nondefault port, redirect refusal, Referer insertion, and no guest headers. Test closed/unknown session IDs and concurrent range requests.
- [ ] Write failing transport tests for HEAD, bounded/open-ended/suffix Range, 206 and 416 headers, disconnect cancellation, slow-but-progressing bodies, and the no-Range behaviour selected by Task 1. For the HTTP fallback, assert loopback-only binding, unpredictable session tokens, unknown-token rejection, and backpressure.
- [ ] Implement the selected transport only; remove unused experimental alternatives. Store validated source mappings in Rust and release them on session close or application teardown. Keep MP4 bytes outside frontend IPC and memory-heavy Blob handling.
- [ ] Write failing preview tests: closing pauses immediately but releases after leave; reopen during leave keeps the new session; an aborted open that later resolves is closed; URL changes destroy only the old player; quality switching retains playback time and uses the selected session's variants.
- [ ] Adapt the shared preview dialog to await `PlaybackPort.open` with loading/error/retry feedback and stale-response guards. Preserve modal focus restoration, cancellation on scope disposal, and no autoplay. Gate PiP/fullscreen controls on actual WebView support.
- [ ] Run `cargo test --manifest-path src-tauri/Cargo.toml --test media` and `pnpm test src/features/programmes/components/ProgrammePreviewDialog.test.ts src/features/programmes/components/ProgrammeVideoPlayer.test.ts src/features/programmes/api`. Recheck installed Windows/macOS playback and update the evidence document.

**Checkpoint:** Both target transports pass the media gate, and shared preview lifecycle tests pass. After Task 7 activates the complete native platform, repeat installed-application playback as part of Task 9; a working development server URL or a unit-tested transport alone cannot satisfy that final acceptance.

### Task 6: Implement Native Downloads and Task Presentation

**Files:** Create `src-tauri/src/downloads/{mod,manager,files}.rs`, `src-tauri/tests/downloads.rs`, `downloads.tauri.ts`, `useDownloadTasksStore.ts`, and `DownloadTasksPanel.vue` with colocated TypeScript tests. Modify `settings.rs`, download composables, archive feedback, command registration, and `AppLayout.vue`.

**Interfaces:** Expose `start_downloads(request: DownloadRequest): DownloadStartResult`, `list_downloads(): DownloadTask[]`, `subscribe_downloads(onEvent: Channel<DownloadTask>): string`, `unsubscribe_downloads(subscriptionId): void`, and `cancel_download(taskId): void`. Extend Task 4's native settings service with `get_download_directory(): string | null` and `choose_download_directory(): string | null`. Produce `NativeDownloadPort`; `subscribe()` returns a function that removes the native subscription. Native task updates include the full task snapshot and monotonic `revision`.

- [ ] Write failing Rust transfer tests using small stubbed MP4 bodies and temporary directories: two-concurrent limit, queued cancellation, running cancellation, unknown total, interrupted body, invalid content type, stale/missing content reference, no available variant, fallback, and independent batch failures.
- [ ] Write failing file tests from shared naming fixtures: invalid characters, reserved Windows names, Unicode/surrogate boundaries, long paths, existing destination, case-only collisions, simultaneous same-name transfers, flush/finalize failure, and cleanup failure. Existing files must retain their original bytes.
- [ ] Implement Rust-owned directory access with the official Dialog and Store plugins, then backend batch preparation and the session-owned manager. Picker cancellation creates no tasks; a missing/inaccessible saved directory fails explicitly. Deduplicate active content/quality/directory tasks, reserve unique filenames without clobbering existing files, stream to task-specific temporary files, and finalize only after successful file closure. Never reset a terminal task through a late progress event.
- [ ] Implement cancellation and teardown so pending HTTP/file operations end and owned temporary artifacts are cleaned. Test recognized leftovers after simulated process interruption without deleting unrelated files. Keep progress updates within the spec's 100 ms interval and deliver terminal updates immediately.
- [ ] Write failing adapter/store tests: subscribe before snapshot; event revision 3 must survive a later snapshot at revision 2; a terminal event arriving during hydration is retained; repeated subscriptions are disposed; navigating away from the archive does not cancel active tasks. Browser `kind` still exposes no native task actions.
- [ ] Implement the Channel bridge and shared task presentation store. Add a desktop-only Naive UI task panel in the shell with filename, actual quality, status, progress/unknown-total indicator, cancel, and retry. Retry calls `start()` with the task content reference and actual quality. Keep per-file failures visible after an accepted batch.
- [ ] Change archive feedback to distinguish browser handoff from native queue acceptance. Cancelling directory selection is silent and creates no tasks; starting a native task does not announce completion. Existing selection and per-row preparation guards continue to work.
- [ ] Run `cargo test --manifest-path src-tauri/Cargo.toml --test downloads`, focused adapter/store/component tests, and native small-file download checks. Verify saved bytes and completed state after real file finalization, not after command acceptance.

**Checkpoint:** A batch can be monitored, cancelled, and retried across page navigation; existing files are preserved. Complete Task 7's directory and exit behaviour before calling this feature finished.

### Task 7: Integrate Persistence, Directory Selection, and Exit Behaviour

**Files:** Create `src-tauri/tests/settings.rs`, `settings.tauri.ts`, and `src/platform/{create-platform,tauri-platform}.ts` with tests. Extend Task 3's Web settings adapter and the native `settings.rs` service established by Tasks 4 and 6. Modify shared persistence, `useSettingsStore.ts`, `SettingsView.vue`, startup, `lib.rs`, `commands.rs`, and relevant capabilities.

**Interfaces:** Expose `load_settings(): SettingsSnapshot` and `save_settings(value: Settings): void`; consume Task 6's directory methods. `SettingsSnapshot` is `{ value: Settings, persisted: boolean }`. Produce the native `SettingsPort`, `createTauriPlatform(): AppPlatform`, and `createAppPlatform(): Promise<AppPlatform>`. Native UUID/directory persistence stays private to Rust.

- [ ] Add failing Web regressions for the exact `sctv-dl:settings` key, schema defaults, cross-tab updates, damaged JSON, denied storage, and the obsolete downloads key remaining unused. Reuse the existing VueUse persistence mechanism rather than introduce a parallel localStorage watcher.
- [ ] Add failing native tests for corrupt store data, denied read/write, stable installation UUID creation, directory removal/permission changes, picker cancellation, and private native values never leaking into the shared settings DTO. Native Dialog and Store operations execute in Rust.
- [ ] Add failing hydration/save-order tests: edit B cannot be overwritten by delayed load A; save B cannot be overwritten by delayed save A; a failed write sets the persistence warning while keeping the user's in-memory value. Serialize native writes and release listeners on disposal.
- [ ] Compose the complete native adapters, select the environment once with `isTauri()`, and dynamically load the native factory. Implement settings hydration before normal app mounting, validated defaults, native plugin-backed saves, and platform-neutral persistence warnings. Provide a recoverable startup error state for unexpected initialization failure. Add the selected directory and native picker affordance to desktop settings while retaining browser-managed copy for Web. Test that each environment selects its own implementation and native development invokes no Node business service.
- [ ] Add the official native application/edit menus and keep ordinary window decorations. Implement a single close-request handler: with active queued/running tasks, reject confirmation to keep working or accept to cancel/clean up before exit. Test repeated close requests and pending directory selection without duplicate prompts or premature process exit.
- [ ] Run `cargo test --manifest-path src-tauri/Cargo.toml --test settings`, settings/persistence/startup tests, and native restart checks for theme, quality, favourites, directory, and UUID. Verify completed task history is not falsely restored as resumable work.

**Checkpoint:** Both targets retain their own preferences correctly; native downloads use a valid user-selected directory; confirmed application exit releases resources.

### Task 8: Finish Shared UI, Routing, and Web Regressions

**Files:** Modify `src/router/index.ts`, router tests, shared layout and programme/settings views as necessary, and their existing tests. Modify `src/styles/global.css` only for genuinely shared theme/motion rules; keep task-panel and feature rules scoped. Update `tooling/vite-startup.test.ts` and module-boundary fixtures for the new sources.

**Interfaces:** Produce `createAppRouter(target: 'web' | 'tauri')`; Web uses history routing and desktop uses hash routing. No programme page or component reads `window.__TAURI__` or imports native APIs; native controls are selected through capabilities.

- [ ] Write failing route tests for Web history, desktop hash navigation/reload, back navigation, cached library scroll restoration, and uncached archive teardown. Retain library search/filter/order/favourite-priority/spotlight behaviour.
- [ ] Write failing shared-view tests for browser-versus-native download feedback, supported native actions only, loading/empty/error/retry states, and session/task cleanup when views unmount. Keep meaningful existing player and archive regressions rather than replace them with shallow mocks.
- [ ] Implement route selection and any remaining shared UI adaptations. Check CSS features against macOS 13's WebKit and provide simple fallbacks where needed. Gate unsupported view-transition/media controls through feature detection; preserve reduced motion.
- [ ] Run `pnpm check` and `pnpm build` once the integrated changes are ready. Fix new type, lint, test, or format failures without reformatting unrelated Android work.
- [ ] Verify Web at desktop and narrow widths in light/dark/system themes, keyboard focus, menu dismissal, modal closing/reopening, loading/empty/error states, settings storage failure, and browser handoff. Verify native resizing, zoom/scaling, keyboard/menu behaviour, and system-theme changes on both platforms. Restore temporary browser preferences and stop preview processes.

**Checkpoint:** The website and desktop applications share the same programme UI, and their platform-specific controls accurately describe implemented capabilities.

### Task 9: Add CI, Validate Installed Applications, and Prepare Distribution

**Files:** Create `.github/workflows/desktop.yml`, `.github/workflows/desktop-release.yml`, and `docs/desktop.md`; update `package.json`, README, `AGENTS.md`, architecture, upstream API, deployment, and media evidence documents. Extend dependency-update configuration to cover Cargo if supported by the repository's existing tooling.

**Interfaces:** Produce scripts `desktop:check` for Cargo formatting/Clippy/tests and `desktop:build` for Tauri packaging. Produce Windows x64 NSIS installers and separate macOS arm64/x64 application/DMG artifacts. The normal Web CI remains intact.

- [ ] Add `desktop:check` running `cargo fmt --manifest-path src-tauri/Cargo.toml -- --check`, `cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets --locked -- -D warnings`, and `cargo test --manifest-path src-tauri/Cargo.toml --locked` using a portable script runner or package scripts. Do not embed machine-specific paths.
- [ ] Add native CI jobs for Windows x64, macOS arm64, and macOS x64. Select runner images with the actual required architecture at implementation time; record `rustc --version`, `node --version`, and `pnpm --version`. Use pnpm's shared cache and Rust build caching, frozen lockfiles, SHA-pinned actions, bounded job timeouts, and read-only repository permissions for validation jobs.
- [ ] Build host applications and installable artifacts in CI. Upload validation artifacts without creating public releases. Run Rust fixture/stub tests, shared frontend checks, and appropriate packaging smoke checks. Treat a build as build evidence only.
- [ ] Add a manual release workflow with explicit version/tag and publication intent. Configure Windows signing and macOS signing/notarization through CI secrets and temporary credential files; do not print secret values. Require signing/notarization credentials for public distribution rather than silently publishing unsigned packages. Use existing official Tauri distribution tooling.
- [ ] Install release-mode packages and execute the acceptance matrix below. Verify fresh install, normal relaunch, paths with spaces/Chinese characters, existing saved preferences, source switching/seeking, directory selection, real-file completion, cancellation/retry, exit confirmation, and launch without Node. Cover both macOS architectures before advertising them as verified.
- [ ] Document current support, setup commands, file locations, native download semantics, pending features, signing requirements, and every unavailable check. Update the durable owning docs and README's documentation map. Keep `/api` raw-proxy and `/client-api/v1` normalized contracts clearly distinguished.
- [ ] Review `git diff --check`, the complete diff, generated artifacts, ignored files, and unintended Android changes. Run the integrated checks below only after relevant changes are final. Once implemented and documented, extract durable constraints and remove the obsolete plan/design checklist in accordance with repository convention.

**Checkpoint:** Report application readiness, each platform's runtime validation, unsigned/signed packaging, and actual publication as separate facts. Do not call the overall Windows/macOS release complete while an advertised target lacks installed-app verification.

## Acceptance Matrix

| Area                                    | Web                                               | Windows x64                                | macOS arm64 / x64                                 |
| --------------------------------------- | ------------------------------------------------- | ------------------------------------------ | ------------------------------------------------- |
| Catalogue, archive, filters, favourites | Browser regressions                               | Installed app                              | Installed app on each architecture                |
| Data validation and cancellation        | Node/adapter/stale-response tests                 | Rust/adapter tests and rapid navigation    | Same plus WKWebView runtime                       |
| Playback, seek, quality, close/reopen   | Existing proxy/browser                            | WebView2 and selected Rust transport       | WKWebView and selected Rust transport             |
| Download                                | HEAD and browser handoff                          | Actual file, queue, progress, cancel/retry | Same on each architecture                         |
| Storage                                 | Existing key, defaults, cross-tab, denied storage | Native restart/corruption/write failures   | Same on each architecture                         |
| Routing and startup                     | Deep links and server fallback                    | Bundled hash routes, no Node               | Same on each architecture                         |
| UI and accessibility                    | Desktop/narrow, both themes, keyboard             | Resize, scaling, menus, focus              | Resize, scaling, application/edit menus, focus    |
| Distribution                            | Production Node remains deployable                | Install/uninstall and signing status       | DMG/install/relaunch, signing/notarization status |

## Verification Commands

These are implementation-time commands, not checks already performed while writing this plan. New desktop scripts exist only after their owning tasks implement them.

```sh
pnpm check
pnpm build
pnpm desktop:check
pnpm desktop:build
git diff --check
```

Run focused commands from each task during development. Run native packaging on each target OS/architecture using the corresponding Tauri target configuration. Do not mistake the host's `pnpm desktop:build` for a build of every platform.

For this planning-only change, run `pnpm format:check`, validate local Markdown links, and inspect the diff. Do not run application tests/builds simply to validate prose.

## Execution and Handoff

Review the proposed OS matrix, first-release download scope, and media gate before implementation. Native execution in the current session is the simplest starting point because the ports, Web backend migration, and Rust services share interfaces. Subagent-driven execution is an optional separately selected method; this plan does not dispatch agents.

Each checkpoint is a reviewable deliverable, not an automatic commit or permission to publish. If commits are requested, use focused English messages along the task boundaries, for example `feat: add normalized programme services for shared clients` and `feat: add native desktop downloads`.

The final implementation handoff must list the changed behaviour, exact commands and runtime cases actually verified, missing platform access or credentials, packaging/signing status, and any scope deviations from this proposal.
