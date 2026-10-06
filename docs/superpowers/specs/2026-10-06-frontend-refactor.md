# Frontend Refactor at the Project Root

The user requested moving the frontend out of web/ into the project root, applying Vue/TypeScript conventions to architecture, blank lines, and necessary comments, and replacing suitable custom infrastructure with established libraries. Existing features and real APIs must remain usable.

Use feature modules under `src/features/programmes`, `downloads`, and `settings`. Keep routing, theme, and app configuration in `src/app`, the application shell in `src/layouts`, shared presentation components in `src/components`, and small shared utilities in `src/shared`. Extract separate archive-request and selection composables, plus components for content lists, date selection, and previews. The server provides local proxies only; browser code must not import server modules.

VueUse replaces manual storage persistence/listeners, system theme subscriptions, and clipboard access. Zod replaces manual API and persisted-record shape validation. Retain native fetch, AbortController, URL, and streaming. Deduplication, quality fallback, and CDN restrictions are domain rules; do not introduce a large framework solely to reduce line count.

Conventions include PascalCase/multi-word components, use-prefixed composables, type-only imports, validation of unknown inputs at boundaries, blank lines between semantic groups, braces around early returns, comments explaining business constraints, one template attribute per line, named actions for complex state mutations, and base/shared styles only in global CSS.

Add regression coverage for damaged storage, task restoration, request races, and quality fallback. Correct the misleading loading label for empty archives. Run all build commands from the root.
