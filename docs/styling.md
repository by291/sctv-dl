# Web Styling

The Web frontend uses native CSS in Vue scoped styles, CSS variables for themes, and Naive UI for controls. Tailwind has been removed from the templates, stylesheets, build, and lint configuration. Direct property names and explicit units make the existing detailed layouts easier to read. Android styling is separate.

## Ownership

| Location                                         | Responsibility                                                                                      |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| [Vue components](../src/layouts/AppLayout.vue)   | Descriptive template classes, component declarations, and responsive rules                          |
| [Global stylesheet](../src/styles/global.css)    | Application defaults, theme variables, shared presentation classes, transitions, and reduced motion |
| [Naive UI theme](../src/theme/naive-ui-theme.ts) | Library colors, typography, sizing, and supported component overrides                               |
| [ESLint configuration](../eslint.config.js)      | Native CSS property, value, and at-rule validation, including Vue style blocks                      |

Keep feature styles with their owning components. Shared selectors such as `.page-heading`, `.pill`, `.notice`, and `.status-dot` belong in the global stylesheet because several components use them. Introduce a shared class or variable when it represents a repeated design decision; isolated measurements do not need individual tokens.

## Readable Declarations

Use native properties with explicit `px` or `rem` units. The root font size is currently `16px`. A `rem` scales with that root size; a `px` is a fixed CSS length. The migrated layouts use explicit pixel measurements to preserve their current dimensions. Unitless `line-height` is a multiplier, and numeric `font-weight` is a weight rather than a length.

For example, the brand's base style in [AppLayout.vue](../src/layouts/AppLayout.vue) is:

```css
.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 0 11px;
  font-size: 24px;
  line-height: 1.2;
  font-weight: 800;
  letter-spacing: -0.8px;
}
```

Keep related responsive adjustments in the same scoped stylesheet. Conditions such as `@media (width < 760px)` exclude the boundary itself. The shell changes from a sidebar to top navigation below this width. The existing narrower spacing and typography adjustments remain to preserve the layout; future changes can simplify them when the design permits.

Mobile layouts support widths down to `320px`. Below `760px`, use one compact navigation bar, retain the connection warning when the service fails, and keep page titles in the content. The programme spotlight is compact, recent dates scroll horizontally, and content entries and settings controls use consistent vertical layouts. Keep native mobile action targets at least `44px` tall. Preview cards reduce padding and clamp long visible titles to two lines while retaining the full accessible text. Player controls use named container queries based on the available video width, so modal padding and screen size cannot select incompatible control layouts.

The shell's `.main-content` owns the shared page width and horizontal padding. Settings panels and the programme library fill that same content area; constrain explanatory text locally instead of narrowing an entire page.

Programme cards, the spotlight, and content entries clamp visible titles to two lines with an ellipsis; cover placeholders use one line. Keep complete titles in the DOM and native title attributes. Content titles open a Naive UI popover on click or keyboard activation, including entries without playable video; Escape dismisses it. Programme detail headings wrap in full. Truncation must not alter source data, accessible action labels, or download filenames.

## Themes and Cascade

Use semantic variables such as `background: var(--panel)`, `color: var(--text)`, and `border: 1px solid var(--line)`. Their values change under `:root[data-theme='dark']`. Naive UI receives its corresponding theme through [App.vue](../src/App.vue).

`NGlobalStyle` in [App.vue](../src/App.vue) applies the configured body typography before the shell mounts, so sidebar fonts and navigation heights do not change when lazy route controls load their preflight styles. Its body and text colors use the application's semantic variables through the theme overrides. Keep Naive UI's preflight enabled for input font inheritance. Application defaults set zero body margins before library components mount and add the border-box model, explicit heading and paragraph spacing, navigation link presentation, and native button typography. CoverImage and Artplayer own media sizing. Do not duplicate a full browser reset or add a reset dependency without a concrete need.

The native `@layer base` contains application defaults. Component and library styles are unlayered, so their normal declarations override those defaults without raising selector specificity. Important declarations reverse this layer order: reduced-motion rules in the base layer retain priority over component animations.

Prefer Naive UI theme overrides for supported control styling. Use scoped classes for layout constraints and `:deep()` for library-generated descendants, such as tab labels and Artplayer controls. The teleported preview card does not inherit its owner's scope attribute, so its unique `.preview-modal` selector uses `:global()` in the owning component. Use `!important` only where library rules compete with an intentional override, or for shared transition and accessibility guarantees.

Keep the root's stable scrollbar gutter and its Naive UI margin-compensation override together. Removing either can shift the page when filtering or opening a modal.

## Motion and Verification

Named keyframes and Vue route/catalogue transitions live in the global stylesheet. Page and content reveals animate opacity only, keeping elements in place. Components opt into those animations explicitly. Preserve reduced-motion handling, catalogue sorting without positional animation, and the modal/player cleanup contract in [Architecture](architecture.md).

Programme card and spotlight links use native View Transitions to move the selected cover into the detail heading over 280ms. Returning to the library through a link or browser history reverses the transition to that same cached source, after its scroll position has been restored. Only the activated source receives the shared name, since the spotlight can repeat a programme from the grid. The return hook releases the existing navigation inside native capture, preserving browser history instead of starting another navigation. It is removed when the source unmounts or the detail route is successfully left; a missing or changed source uses ordinary navigation. The route shell temporarily disables its Vue CSS transition and sequential leave/enter mode so the destination is mounted before native capture; the native root transition supplies the page fade without positional movement. Modified clicks retain normal link behaviour, and reduced-motion preferences or unsupported browsers use ordinary navigation. A newer navigation invalidates a deferred transition callback. Transient state is cleared after completion, aborted navigation, or capture failure.

[CSS lint tests](../tooling/css-lint.test.ts) verify that invalid declarations are reported in both standalone CSS and Vue styles, while responsive rules and references to external theme variables remain valid. ESLint validates individual stylesheets; it does not resolve variables across files.

For styling changes, run `pnpm check` and `pnpm build`, then verify affected pages at desktop and narrow widths in light and dark themes. Check keyboard interaction and affected loading, empty, and error states. For documentation-only changes, run `pnpm format:check` and verify local links and referenced commands.
