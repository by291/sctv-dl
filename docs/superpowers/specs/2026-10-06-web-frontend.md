# sctv-dl Web: Initial Version

> Historical specification: the frontend was subsequently moved to the project root. See README, CONTRIBUTING, and docs/architecture.md for the current layout and conventions.

The user selected a browser frontend under the root-level `web/` directory and authorized implementation.

Stack: Vue 3, TypeScript, Vite, Naive UI, Pinia, Vue Router, native fetch, pnpm, ESLint, and Prettier.

The first version includes a programme library, details, download tasks, and settings. It uses three verified public programme endpoints and preserves IDs as strings. Users can search programmes, select available broadcast dates, choose full episodes or clips, switch between standard and smooth quality, and add tasks in batches.

A local Vite proxy handles API and video requests, adding the required Referer for media. The media proxy permits only the verified HTTPS CDN and does not follow external redirects. The browser download manager owns saving, progress, cancellation, and resume. Web task state describes queuing or browser handoff without claiming successful file completion. Static deployments require corresponding service proxies.

The interface uses real data and exposes loading, empty, error, and retry states. It does not include fabricated tasks or progress. Preferences and task metadata are stored locally.

The initial scope excludes the Rust SDK, desktop shell, authentication, live streams, cloud deployment, and APK source code.
