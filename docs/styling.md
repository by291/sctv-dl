# Web Styling Assessment

The Web frontend uses Naive UI for controls and Tailwind CSS for application styles. For this project, extensive `@apply` rules and fine-grained numeric utilities add reading cost without enough benefit to make them the preferred long-term approach. The proposed direction is to use native CSS in Vue scoped styles for substantial component rules, while retaining CSS variables for themes and Naive UI for controls.

This is a styling proposal. The current Tailwind conventions in [AGENTS.md](../AGENTS.md) remain active until they are updated as part of an implementation change. Android styling is outside this scope.

## Current Approach

| Location                                       | Responsibility                                                                          |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- |
| [Vue components](../src/layouts/AppLayout.vue) | Short template utilities and named scoped classes composed with `@apply` and `@variant` |
| [Global stylesheet](../src/styles/global.css)  | Tailwind entry, theme variables, base rules, shared classes, and motion                 |
| [Naive UI theme](../src/app/theme.ts)          | Component-library colors, typography, sizing, and component overrides                   |
| [ESLint configuration](../eslint.config.js)    | Utility ordering, canonical forms, conflicts, and CSS syntax checks                     |

The root font size is explicitly `16px`, and Tailwind lint uses the same value. The global stylesheet maps semantic utilities such as `bg-panel` and `text-main` to CSS variables whose values change with the active theme. Naive UI receives its theme separately through [App.vue](../src/App.vue).

## Useful Parts of Tailwind

Short utilities can make small layouts quick to write and easy to inspect. Semantic color utilities share the same theme values across components. Tailwind also provides consistent conventions for responsive conditions and interaction states, and the existing lint rules detect conflicting or duplicate utilities.

These benefits are useful where the utility names express a familiar, compact composition. They become less compelling when a long list of utilities is already hidden behind a named CSS class and many values need individual adjustment.

## Sources of Reading Cost

### Numeric Translation

The default spacing unit is `0.25rem`. At the current `16px` root size, `gap-2.75` means `11px`, `px-3.75` means `15px` of horizontal padding, and `h-18.75` means `75px` of height. Readers must translate these numbers before understanding the geometry.

The canonical-class rule reinforces this representation. The [tooling tests](../tooling/tailwind-lint.test.js) require `w-[232px]` to become `w-58`, including inside `@apply`. Converting an exact measurement into a numeric utility changes its spelling; it does not itself establish a simpler spacing scale.

### Styles Across Several Locations

A component's appearance can depend on template utilities, its scoped stylesheet, global theme variables, and Naive UI overrides. This separation has valid ownership reasons, but readers must move between these locations to understand the final result.

For example, `bg-panel` refers through the Tailwind theme mapping to `--panel`, whose value differs between light and dark themes. Native CSS can retain the same theme behavior with `background-color: var(--panel)` while making that dependency explicit.

### Detailed Responsive Overrides

[AppLayout.vue](../src/layouts/AppLayout.vue) adjusts the sidebar, brand, navigation, topbar, and content at several viewport widths, including `1250px`, `1020px`, `760px`, and `440px`. The change from a desktop sidebar to a mobile top bar serves a real layout requirement. Separate adjustments to font sizes and padding increase the number of rules readers must follow.

Replacing Tailwind syntax alone would leave those conditions intact. Reducing this complexity also requires reviewing whether each adjustment is needed and whether related elements can share a simpler layout rule.

### CSS Rules Written Through Utility Names

The brand already has a descriptive selector, but its declarations still use Tailwind syntax:

```css
.brand {
  @apply flex items-center gap-2.75 px-2.75 text-2xl leading-[1.2] font-extrabold;
  @apply tracking-[-0.8px];
}
```

At the current root size and default spacing and typography values, its base appearance can be expressed directly:

```css
.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  padding-inline: 11px;
  font-size: 1.5rem;
  line-height: 1.2;
  font-weight: 800;
  letter-spacing: -0.8px;
}
```

The second form exposes property names and units. `line-height: 1.2` is a native CSS multiplier, and `font-weight: 800` is a native weight value; neither needs a length unit. The existing responsive overrides would still need corresponding native `@media` rules.

## Proposed Styling Conventions

Use named classes and native declarations in the owning component's scoped stylesheet for substantial component styles. Keep related responsive conditions beside those declarations. Short template utilities can remain useful while Tailwind is still present.

Keep shared theme values, base styles, named transitions, and reduced-motion handling in the global stylesheet. Keep feature styles with their components. Continue using Naive UI theme overrides for supported control sizing and appearance.

Choose explicit `px` or `rem` values according to the intended behavior. `rem` expresses scaling with the root font size; `px` expresses a fixed CSS length. Conversion should preserve that distinction rather than replacing every value mechanically. Preserve semantic color variables so light and dark themes continue to work.

Favor a small set of recurring spacing and typography values where the design allows it. Keep exact measurements when an element actually needs them. Add shared variables or classes for repeated design decisions rather than introducing a token for every isolated value.

## Incremental Adoption

Simplify components when they need styling work, with each change preserving the intended appearance and interaction. Update the relevant Tailwind conventions in [AGENTS.md](../AGENTS.md) when native component CSS becomes the adopted approach. Keep lint rules and their tooling tests aligned with the syntax that remains in use.

Tailwind removal is a separate final cleanup, after template utilities, `@apply`, `@variant`, and theme mappings have been replaced. That cleanup must also account for the Tailwind import in the global stylesheet, the [Vite plugin](../vite.config.ts), and related dependencies, lint configuration, and tooling tests. Naive UI remains responsible for its controls.

For actual styling changes, run `pnpm check` and `pnpm build`, then verify affected pages at desktop and narrow widths in light and dark themes. Include keyboard interaction and affected loading, empty, and error states. Preserve reduced-motion behavior and the player and modal lifecycle described in [Architecture](architecture.md).

For documentation-only updates, run `pnpm format:check` and verify local links and referenced commands.

## References

- [Tailwind directives](https://tailwindcss.com/docs/functions-and-directives): `@apply`, `@variant`, and `@reference`.
- [Tailwind spacing utilities](https://tailwindcss.com/docs/gap): numeric values use the theme spacing unit.
- [Tailwind responsive design](https://tailwindcss.com/docs/responsive-design): breakpoint conditions and arbitrary widths.
- [Vue scoped CSS](https://vuejs.org/api/sfc-css-features.html): styles owned by individual components.
