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
      components/          Cards, spotlight, date picker, content list, download menu, preview dialog
      views/               Library and details page composition
    downloads/
      schema.ts            Stored task validation
      model.ts             Filenames, task creation, deduplication, recovery
      browser-download.ts  HEAD preflight and browser handoff
      store.ts             Shared queue, actions, persistence
      components/          Task row presentation
      views/               Queue page composition
    settings/
      schema.ts / store.ts Preference validation and shared state
      views/               Settings UI
  shared/                  Persistence, errors, media URLs, request guards
  styles/global.css        Tailwind entry, theme tokens, shared styles and motion
server/                    Local API and streaming media proxies
```

Views compose components and composables. Stores own shared state. Business functions depend on domain types and schemas. APIs accept unknown data and return validated types. Shared modules do not import feature stores. Browser code does not import Node server modules.

## Data Flow

The programme store caches the catalogue. useProgrammeArchive manages dates, content, loading, errors, and request cancellation. useContentSelection manages selection and full-episode matching independently of quality. ProgrammeDownloadButton shares the click-triggered Naive UI quality dropdown across individual rows and the batch action. Unavailable variants are disabled. Selecting a quality converts the current requested contents into tasks and shows one notification, including any fallback, without navigating away. Dismissing the menu leaves the queue unchanged. Changing the selection closes its pending menu; replacing archive contents unmounts download menus and closes the preview. The preview dialog owns player errors and media URLs.

useFeaturedProgramme selects a random catalogue entry when the library view is created. The spotlight's shuffle action excludes the current programme. Searching, filtering favourites, and refreshing the catalogue preserve the selected ID; refreshed metadata is resolved from the current catalogue. A removed programme is replaced, and changing is disabled when fewer than two entries exist. There is no automatic rotation or persisted selection.

AbortController cancels requests, while LatestRequest prevents obsolete responses from committing state. Requests are cancelled when their component scope ends. Content is not requested without a broadcast date.

Cover and video fields are optional at the API boundary and normalize to null. The service can omit `videoStandard` for clips with only a standard variant; that must not invalidate the other contents in a broadcast. IDs, response envelopes, and calendar dates remain strictly validated. Error panels describe a loading failure without assuming a network outage, and content counts appear only after a successful request.

Settings and favourites retain the `sctv-dl:settings` key; tasks retain `sctv-dl:downloads`. Invalid JSON falls back to defaults. An invalid preference field uses its own default, and individual invalid task records are discarded. New or invalid theme preferences default to system; valid saved choices are retained. The saved quality preference sets initial preview quality; each download operation chooses its own quality in the menu. Interrupted `checking` tasks return to `queued` during initialization. Valid tasks are retained without silently truncating the queue on reload.

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

The top bar shows the current page title, while the sidebar owns the app brand. The document reserves scrollbar space with `scrollbar-gutter: stable` so the library remains aligned when a filtered list becomes shorter than the viewport. Where stable gutters are supported, root margins suppress Naive UI's additional scrollbar compensation during modal scroll locking. The modal keeps its scroll lock and focus trap without narrowing the background page.

Catalogue sorting always places favourites first. Default sorting retains service order within the favourite and non-favourite groups; name sorting orders each group separately. Search and the favourites tab use the same ordering. The theme setting exposes system, light, and dark as radio buttons in that order, and only the archive refresh button indicates date-toolbar loading. The content header aligns the date, title, and count on a shared baseline and places the batch action above the list; every available row has its own download action.

## Motion and Video Preview

Motion uses Vue Transition / TransitionGroup with short transition names and Tailwind-composed rules in `src/styles/global.css`. Most transitions last 140-180ms and animate opacity or small transforms. Page wrappers provide a single transition root even when a view has multiple root nodes. The router passes the programme ID as a view prop so a departing view retains its own request identity during the transition. Scrollbar space remains reserved during list filtering.

| Surface                 | Motion decision                                                                                                                                                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Navigation and settings | Brief page transition; the sidebar and top bar remain stable. Existing Naive UI input and dropdown transitions are retained.                                                                                                               |
| Programme library       | Newly visible catalogue entries fade in. Sorting and favourite priority changes reorder immediately without movement across the grid. The spotlight title and poster reveal on manual shuffle; favourite icons provide brief confirmation. |
| Broadcast archive       | Loading, empty, and error panels reveal gently. Loaded content fades in; date choices and selected rows transition their colours.                                                                                                          |
| Download queue          | New and removed tasks fade, remaining rows move, and status changes crossfade.                                                                                                                                                             |
| Preview dialog          | Keep Naive UI's existing modal and focus management. Artplayer owns playback controls and their transitions.                                                                                                                               |

The reduced-motion media query shortens custom and library animations to effectively immediate changes. There are no automatic carousels, staggered delays for long lists, or animated numeric counters.

ProgrammeVideoPlayer wraps [Artplayer](https://artplayer.org/document/en/) with Chinese controls, playback speed, keyboard shortcuts, picture-in-picture, and fullscreen. The browser still decodes MP4 media. The preview retains the existing quality fallback and `/media` proxy and requests metadata without autoplay. video.ts lists distinct available variants, omitting duplicate URLs. When two variants are available, an Artplayer settings selector switches quality through switchQuality, preserving playback position within the same instance. The initial resolved URL keys the component; closing the dialog, changing the preview, or leaving the page pauses and destroys the instance. Initialization, media, and quality-switch failures propagate to the dialog's error message, which clears when metadata loads successfully. Tests cover quality selection, immediate queue creation, notifications, fallbacks, menu dismissal, player integration, cleanup, and failures; browser verification covers the actual library UI and playback.

## Readability Improvements

- App.vue mixed theme detection, component library configuration, and layout; these now live in a theme composable, configuration module, and layout component.
- ProgrammeView mixed requests, selection, playback, and task creation; requests and selection are separate composables, while date selection, content rows, and previews have typed component contracts.
- Download rows used nested status ternaries; a typed map now defines labels, icons, and actions.
- Vue closing tags were crowded; Prettier whitespace/attribute settings and semantic spacing make the markup readable.
- Short Tailwind utility combinations remain in component templates. Complex responsive styles and repeated component patterns use scoped `@apply` rules, with `@variant` blocks grouping breakpoints and `@reference` reusing the theme without duplicate output. Shared styles and named transitions live in the Tailwind entry; feature-specific rules remain with their owning components.
- Browser and server ambient types were mixed; TypeScript and ESLint environments are configured separately.
- Conventions depended on memory; EditorConfig, Prettier, ESLint, and pnpm check enforce the mechanical rules.
