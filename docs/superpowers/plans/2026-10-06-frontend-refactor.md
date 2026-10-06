# Frontend Refactor Plan

> Historical plan: Git was not initialized during the refactor. Subsequent user instructions authorize repository initialization and the initial commit.

**Goal:** Run from the root with maintainable structure/conventions and library support for appropriate infrastructure.
**Architecture:** Feature-oriented Vue pages, composable state, shared Pinia stores, and an independent local proxy.
**Tech Stack:** Vue / TS / Vite / Pinia / Naive UI / VueUse / Zod / ESLint / Prettier / Vitest.
**Spec:** `docs/superpowers/specs/2026-10-06-frontend-refactor.md`.

## Global Constraints

- The user authorized directory migration, architecture/convention improvements, and suitable library replacements.
- Without a Git repository at the time, preserve local changes and execution records without creating branches or commits.
- Preserve string IDs, real APIs, storage keys, media target restrictions, and truthful browser handoff states.
- Libraries provide general capabilities; business logic remains understandable and independently verifiable.

## Task 1: Move and Tooling

Validate absolute paths, move web content to the root, and update README, cache paths, package name, scripts, and formatting rules. Install VueUse, Zod, and Stylistic.

Expected: pnpm test/build/lint run from the root, and web/ no longer contains the application.

## Task 2: Data and Shared State

Move existing tests alongside feature modules. Add boundary/recovery regressions and observe RED before implementation. Separate schemas, API normalization, browser handoff, and persistence.

Expected: existing and new tests are GREEN; runtime input is validated through explicit schemas.

## Task 3: Composables and Components

Write request-switching and empty-archive tests before implementation. Extract request/selection composables, detail components, layout, and theme logic. Split CSS and add semantic spacing and business comments.

Expected: views compose pages, and request-race/quality-fallback tests are GREEN.

## Task 4: Verify and Review

Write CONTRIBUTING and architecture/library-decision documentation. Run tests, type checks/build, lint, formatting checks, real API/Range checks, and browser regressions. Perform one independent read-only final review under the executing-plans workflow and repair important defects.

Expected: all checks pass and a working local preview is available.

## Review Focus

- Are root paths, caches, build configuration, and documentation consistent?
- Are request cancellation, obsolete-result guards, and scope disposal safe?
- Does VueUse persistence preserve existing data and recover from damaged records and cross-tab replacements?
- Does Zod preserve large string IDs, optional videos, missing fields, and helpful errors?
- Do component boundaries and stylesheet ownership preserve responsive layout and events?
