# Architecture and Library Decisions

The frontend was moved from web/ to the repository root. Run installation, development, test, and build commands from the root.

## Structure and Responsibilities

```text
src/
  app/                     Routing, Naive UI configuration, theme synchronization
  layouts/                 Navigation and top bar
  components/              Shared covers and loading/error/empty states
  features/
    programmes/
      schemas.ts           Upstream validation and field normalization
      api.ts               Three programme APIs and localized errors
      types.ts             Domain types inferred from schemas
      urls.ts / video.ts   URL normalization and available quality selection
      store.ts             Shared programme catalogue cache
      composables/         Archive lifecycle, content selection, programme discovery
      components/          Cards, spotlight, date picker, content list, preview dialog
      views/               Library and details page composition
      styles.css           Programme UI and responsive styles
    downloads/
      schema.ts            Stored task validation
      model.ts             Filenames, task creation, deduplication, recovery
      browser-download.ts  HEAD preflight and browser handoff
      store.ts             Shared queue, actions, persistence
      components/          Task row presentation
      views/               Queue page composition
      styles.css
    settings/
      schema.ts / store.ts Preference validation and shared state
      views/ / styles.css  Settings UI
  shared/                  Persistence, errors, media URLs, request guards
  styles/global.css        Theme variables, resets, common styles
server/                    Local API and streaming media proxies
```

Views compose components and composables. Stores own shared state. Business functions depend on domain types and schemas. APIs accept unknown data and return validated types. Shared modules do not import feature stores. Browser code does not import Node server modules.

## Data Flow

The programme store caches the catalogue. useProgrammeArchive manages dates, content, loading, errors, and request cancellation. useContentSelection manages quality, selection, and full-episode matching. The page converts selected content into tasks and passes them to the download store. The preview dialog owns player errors and media URLs.

useFeaturedProgramme selects a random catalogue entry when the library view is created. The spotlight's shuffle action excludes the current programme. Searching, filtering favourites, and refreshing the catalogue preserve the selected ID; refreshed metadata is resolved from the current catalogue. A removed programme is replaced, and changing is disabled when fewer than two entries exist. There is no automatic rotation or persisted selection.

AbortController cancels requests, while LatestRequest prevents obsolete responses from committing state. Requests are cancelled when their component scope ends. Content is not requested without a broadcast date.

Cover and video fields are optional at the API boundary and normalize to null. The service can omit `videoStandard` for clips with only a standard variant; that must not invalidate the other contents in a broadcast. IDs, response envelopes, and calendar dates remain strictly validated. Error panels describe a loading failure without assuming a network outage, and content counts appear only after a successful request.

Settings and favourites retain the `sctv-dl:settings` key; tasks retain `sctv-dl:downloads`. Invalid JSON falls back to defaults. An invalid preference field uses its own default, and individual invalid task records are discarded. Interrupted `checking` tasks return to `queued` during initialization. Valid tasks are retained without silently truncating the queue on reload.

Settings use VueUse synchronization across browser tabs. Downloads execute within the current window and do not synchronize execution state across windows. Concurrent windows still use last-write-wins persistence. Multi-window queue coordination would require a single executor and a deliberate merge policy.

## Replaced Custom Infrastructure

| Previous implementation                                                       | Current approach                              | Benefit                                                                |
| ----------------------------------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| localStorage access and deep watchers                                         | VueUse useStorage with a small schema adapter | Reactive persistence, managed listeners, consistent error feedback     |
| matchMedia listeners, HTML theme updates, lifecycle cleanup                   | VueUse useColorMode                           | System theme support and reuse of the existing settings state          |
| navigator.clipboard.writeText                                                 | VueUse useClipboard                           | Existing compatibility handling and legacy copy fallback               |
| Manual object/array checks, field guards, date regex, stored record filtering | Zod schemas                                   | Central runtime validation, field defaults, inferred types             |
| Manually adding/removing IDs for each checkbox                                | Naive UI NCheckboxGroup                       | Direct selection binding with explicit select-all/full-episode actions |
| Repeated find calls for task deduplication                                    | Native Set                                    | Linear deduplication while preserving existing task state              |

The replacements follow [VueUse useStorage](https://vueuse.org/core/useStorage/), [useColorMode](https://vueuse.org/core/useColorMode/), [useClipboard](https://vueuse.org/core/useClipboard/), and [Zod Basics](https://zod.dev/basics).

## Retained Small Implementations

| Implementation                                               | Rationale                                                                                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Native fetch for three GET endpoints                         | The current request policy is simple. Reconsider Axios/ky or a query library when authentication, complex retries, or caching require it.        |
| Request switching guard                                      | AbortController plus a small version guard is sufficient. Cancellation alone does not prevent an obsolete result from overwriting current state. |
| URL parsing, ISO date sorting, Set deduplication             | Platform features suffice without additional URL, date, or utility libraries.                                                                    |
| Full-episode matching, quality fallback, filenames, task IDs | These are downloader business rules expressed as named, independently testable functions.                                                        |
| Browser download handoff                                     | The native download manager owns saving and actual progress without buffering hundreds of MB in a page Blob.                                     |
| Node streaming proxy                                         | Native stream/pipeline provides backpressure. CDN restrictions, Referer, and Range handling are explicit service constraints.                    |

The proxy middleware runs inside Vite's existing development or preview server, sharing its process and port. It is not a separately started service. The API currently allows cross-origin metadata requests, but media requests still require a Referer from the upstream player origin that browser Fetch cannot supply. Production can serve static files and the media route from one application server; this runtime is not implemented yet. A native desktop or mobile HTTP implementation can satisfy the media header requirement without a local HTTP proxy process.

The shared typography uses 16px body text and a 14px minimum for supporting labels, with matching Naive UI theme settings. Page titles describe the current task, and helper text is reserved for choices and behaviour that affect the user.

The top bar shows the current page title, while the sidebar owns the app brand. The document reserves scrollbar space with `scrollbar-gutter: stable` so the library remains aligned when a filtered list becomes shorter than the viewport.

## Motion and Video Preview

Motion uses Vue Transition / TransitionGroup and shared CSS durations in `src/styles/motion.css`. Most transitions last 140-180ms and animate opacity or small transforms. Page wrappers provide a single transition root even when a view has multiple root nodes. The router passes the programme ID as a view prop so a departing view retains its own request identity during the transition. Scrollbar space remains reserved during list filtering.

| Surface                 | Motion decision                                                                                                                                                                                        |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Navigation and settings | Brief page transition; the sidebar and top bar remain stable. Existing Naive UI input and dropdown transitions are retained.                                                                           |
| Programme library       | Catalogue entries fade in and move when filtered or sorted. The spotlight title and poster reveal on manual shuffle without remounting the focused button. Favourite icons provide brief confirmation. |
| Broadcast archive       | Loading, empty, and error panels reveal gently. Loaded content fades in; date choices and selected rows transition their colours.                                                                      |
| Download queue          | New and removed tasks fade, remaining rows move, and status changes crossfade.                                                                                                                         |
| Preview dialog          | Keep Naive UI's existing modal and focus management. Artplayer owns playback controls and their transitions.                                                                                           |

The reduced-motion media query shortens custom and library animations to effectively immediate changes. There are no automatic carousels, staggered delays for long lists, or animated numeric counters.

ProgrammeVideoPlayer wraps [Artplayer](https://artplayer.org/document/en/) with Chinese controls, playback speed, keyboard shortcuts, picture-in-picture, and fullscreen. The browser still decodes MP4 media. The preview retains the existing quality fallback and `/media` proxy, requests metadata without autoplay, and keys each player by its resolved URL. Closing the dialog, changing source, or leaving the page pauses and destroys the instance. Initialization and media errors propagate to the dialog's error message. Player lifecycle tests cover cleanup and failures; browser verification covers the actual library UI and playback.

## Readability Improvements

- App.vue mixed theme detection, component library configuration, and layout; these now live in a theme composable, configuration module, and layout component.
- ProgrammeView mixed requests, selection, playback, and task creation; requests and selection are separate composables, while date selection, content rows, and previews have typed component contracts.
- Download rows used nested status ternaries; a typed map now defines labels, icons, and actions.
- Vue closing tags were crowded; Prettier whitespace/attribute settings and semantic spacing make the markup readable.
- One long stylesheet covered the entire application; feature styles and scoped shared component styles now have clear ownership.
- Browser and server ambient types were mixed; TypeScript and ESLint environments are configured separately.
- Conventions depended on memory; EditorConfig, Prettier, ESLint, and pnpm check enforce the mechanical rules.
