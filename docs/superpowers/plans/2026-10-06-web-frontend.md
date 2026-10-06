# Web Frontend Implementation Plan

> Historical plan: the frontend was subsequently moved to the project root. See README, CONTRIBUTING, and docs/architecture.md for current paths and conventions. The repository did not exist during this implementation; later user instructions authorize Git initialization and an initial commit.

**Goal:** Deliver real programme browsing and browser downloads in `web/`.
**Architecture:** Vue pages and Pinia stores use an independent TypeScript API client; Vite development/preview middleware proxies API and media requests.
**Tech Stack:** Vue 3 / TypeScript / Vite / Naive UI / Pinia / Vue Router / Vitest / pnpm / ESLint / Prettier.
**Spec:** `docs/superpowers/specs/2026-10-06-web-frontend.md`.

## Global Constraints

- Implement the frontend in root-level `web/`; preserve large API IDs as strings.
- Handle API business errors and keep date IDs separate from date text.
- Do not fabricate completed-download states. Restrict proxy hosts and reject redirects.
- The project started empty without Git. Work in the user-selected directory and do not create commits without user authorization.

## Task 1: Tooling and Data Boundaries

Files: `web/package.json`, `web/vite.config.ts`, `web/src/api/*`, `web/server/*`, and corresponding `*.test.ts`.
Produces: typed Programme/ProgrammeDate/ProgrammeContent, API client, and media guard.

Steps:

- [ ] Create tool configuration and API/media input validation tests. Run tests. Expected: failures due to missing implementations.
- [ ] Implement normalization, error handling, and path-restricted proxies. Run tests. Expected: all pass.

## Task 2: Pages and Download Tasks

Files: `web/src/stores/*`, `web/src/views/*`, `web/src/components/*`, `web/src/App.vue`, and `web/src/style.css`.
Consumes: Task 1 string IDs, standard/smooth content models, and proxy URLs.
Produces: library/details/queue/settings pages, persisted tasks, and request cancellation.

Steps:

- [ ] Write tests for queue deduplication, quality fallback, filenames, and damaged storage recovery. Expected: missing-implementation failures.
- [ ] Implement stores, pages, and responsive layout. Run tests and build. Expected: pass.

## Task 3: Integration Verification and Documentation

Files: `README.md`, `web/README.md`, and `.env.example`.

Steps:

- [ ] Verify real APIs, media Range delivery, rejection of invalid targets, and browser interactions without downloading a complete large episode.
- [ ] Run tests, type checks/build, lint, and formatting checks. Expected: all pass.
- [ ] Perform one fresh-context review, fix important issues with regression tests, and open the local preview.

## Review Focus

- Can obsolete requests overwrite the current programme/date?
- Do task states falsely claim completion, or can batch downloads trigger duplicates?
- Can the media proxy reach disallowed hosts, follow redirects, or inject response headers?
- Can damaged local storage prevent application startup?
- Can empty dates, missing smooth variants, and offline errors recover?
