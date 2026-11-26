# Yab2 Application Shell Design System

This document defines visual and interaction requirements for an application shell based on Yab2. It is independent of implementation language, platform toolkit, and component library. Measurements are in CSS pixels or equivalent logical units. The semantic token names in this document may be mapped to a design system's existing schema; shadcn-compatible names appear in parentheses where useful.

## 1. Design principles

- The active workspace owns the shell background. Navigation and content areas share that visual context.
- Use neutral light and dark surfaces, restrained borders, and low-contrast selection and hover fills.
- Treat spacing, density, typography, icon sizing, and corner radius as one coordinated system.
- Use a soft filled surface to show selection. Do not use an outline as the default selected state.
- Give navigation items a leading icon or mark. Keep the icon slot consistent across rows.
- Keep labels compact, single-line, and readable. Use hierarchy through weight and color rather than large type.
- Preserve the same structure and interaction states across desktop layouts and responsive variants.

## 2. Color and surface tokens

Use semantic color roles so components remain readable when the active workspace changes its background.

| Role | Optional shadcn token | Light reference | Dark reference | Purpose |
| --- | --- | --- | --- | --- |
| App background | `background` | `#FFFFFF` | `#1C1C1C` | Base surface behind the shell; may be overridden by workspace appearance |
| Primary text | `foreground` | `#171717` | `#EDEDED` | Main labels and content |
| Secondary text | `muted-foreground` | Neutral gray | Light neutral gray | Supporting labels and inactive icons |
| Faint text | — | Mid neutral gray | Mid-light neutral gray | Tertiary metadata; retain readable contrast |
| Card surface | `card` | Slightly off-white | Slightly lighter than background | Explicitly elevated content only |
| Popover surface | `popover` | Opaque light surface | Opaque dark surface | Menus and floating controls |
| Hairline | `border` | `#E8E8E8` | `#333333` | Dividers and subtle boundaries |
| Field boundary | `input` | Medium-light neutral | Medium-dark neutral | Makes input boundaries discoverable |
| Hover surface | `accent` or `muted` | Low-opacity dark wash | Low-opacity light wash | Hover and transient highlight |
| Selected surface | `secondary` or dedicated selection token | Neutral wash | Neutral wash | Selected navigation row |
| Action accent | `primary` | Application-defined | Application-defined | Primary actions and explicit brand accents |
| Action text | `primary-foreground` | Contrast-safe | Contrast-safe | Text on primary actions |
| Destructive | `destructive` | Semantic red | Semantic red | Destructive labels and actions |
| Focus ring | `ring` | Clear blue or accessible accent | Clear blue or accessible accent | Keyboard focus indication |
| Navigation surface | `sidebar` | Inherited background plus shade | Inherited background plus shade | Sidebar and rail surface |
| Navigation text | `sidebar-foreground` | Same text roles above | Same text roles above | Navigation labels |
| Navigation border | `sidebar-border` | Hairline | Hairline | Rare navigation dividers |
| Navigation focus | `sidebar-ring` | Same as focus ring | Same as focus ring | Focus within navigation |

Approximate neutral values are references, not a fixed brand palette. Derive secondary labels, hover fills, and selection fills from neutral ink with opacity so they adapt to custom workspace backgrounds. Do not apply the action accent to ordinary selected navigation rows.

### Surface rules

- The application shell uses one shared workspace background layer.
- Sidebar and rail surfaces remain visually connected to that layer. Use a subtle shade or translucent overlay instead of unrelated opaque panels.
- Keep shell containers transparent unless they represent an explicit card, menu, or floating panel.
- Use a raised card surface only for content that needs separation. Avoid wrapping every navigation group or page region in a card.
- Edge-to-edge content has square corners and no outer page inset.
- Embedded content may use its own background.
- Menus and popovers must remain legible over any workspace background. An opaque surface is acceptable for these floating layers.

## 3. Workspace background appearance

The background feature styles the application shell canvas for each workspace. It is not a page banner or decorative card. The same background identity extends behind the rail, sidebar, and main shell area, while each region may use a subtle readability overlay.

### Appearance properties

Store these as independent workspace appearance properties:

| Property | Specification |
| --- | --- |
| Base color | A preset or custom color; include a neutral/no-tint choice |
| Gradient colors | Optional: up to two additional colors, for three total stops |
| Gradient direction | Diagonal from top-left to bottom-right |
| Grain | Independent amount from 0 to 100%; default around 35% |
| Decorative pattern | None or one selected pattern family |
| Pattern intensity | Independent amount from 0 to 100%; default around 45% when a pattern is selected |
| Transparency | 0–100%; adjusts how much of the underlying canvas is revealed |
| Appearance mode | Follow application theme by default; optionally allow workspace Light or Dark mode |

Offer compact controls for color selection, gradient stops, texture choice, texture intensity, and transparency. Changing one property must preserve the others. Provide a reset-to-default action.

### Texture behavior

- Grain is a fine, evenly tiled noise texture. At the default amount it should be barely visible, like paper grain. It must not introduce visible clumps, bands, or a repeating large-scale pattern.
- Decorative patterns are sparse, seamless, low-contrast line illustrations. Example pattern families: product-related icons, everyday objects, and seasonal motifs.
- A pattern is repeated across the shell canvas, not attached to individual components. Keep pattern marks recognizable but subordinate to text and controls.
- Adjust pattern ink for light and dark backgrounds. Use dark marks on light backgrounds and light marks on dark backgrounds, with restrained opacity.
- Grain and decorative pattern are separate layers and can be combined. Grain must not be used as a substitute for decorative artwork.

### Layer order and shell integration

Render the shell background in this order:

1. Base solid color or diagonal gradient.
2. Optional grain texture.
3. Optional decorative pattern.
4. Shell regions: transparent content canvas, with subtle shading on navigation surfaces where needed.
5. Foreground controls and content.

Transparency affects the color/gradient coating while preserving content clarity. If blur or a glass effect is supported, it belongs behind the coating and must never blur text, icons, or controls. When reduced transparency is enabled, use an opaque fallback. Maintain readable text and icon contrast across all background combinations.

### Persistence and switching

- Save appearance per workspace and restore it when that workspace becomes active.
- Apply appearance edits live while the editor is open.
- Switching workspaces updates the shell background and navigation tint together. The transition should not cause navigation to lose contrast or flash an empty background.
- Changing base color preserves gradient configuration, texture, transparency, and appearance mode. Changing texture preserves all color values.
- Respect reduced-motion and reduced-transparency preferences.

## 4. Geometry and density

Use a 4px base spacing unit. The reference values below may be adjusted to fit a host platform, but related geometry must remain consistent.

| Element | Comfortable | Compact | Use |
| --- | ---: | ---: | --- |
| Base spacing unit | 4px | 4px | General spacing |
| Navigation row height | 36px | 28px | Destinations, tabs, section heading |
| Vertical row gap | 5px | 4px | Navigation rhythm |
| Icon slot | 16px | 15px | Fixed leading mark area |
| Icon-to-label gap | 10px | 8px | Row content |
| Row leading inset | 10px | 10px | Content inside full-width hit target |
| Row trailing inset | 11px | 7px | Space for row actions |
| Row corner radius | 10px | 8px | Hover and selected surface |
| Outer shell inset | 12px | 12px | Shell edge and navigation content |
| Hit target | Full row | Full row | Larger than visible text or icon |

The desktop navigation column is approximately 272px wide overall, including the narrow rail. The rail is about 60px at comfortable density or 52px compact, leaving about 212px for sidebar content at the default comfortable width. The full column may resize from 240px to 420px. On narrow screens, use a drawer or icon rail rather than compressing labels beyond usability.

### Radius scale

| Token | Value | Use |
| --- | ---: | --- |
| Small | 5px | Keycaps, tags, small badges |
| Control | 8px | Buttons, inputs, compact controls |
| Row / surface | 10px | Comfortable navigation rows and content cards |
| Floating panel | 14px | Popovers and larger floating surfaces |
| Outer frame | 18px | Rounded application/window frame only |

Use continuous-looking corners. Keep nested highlights concentric with the parent control. Avoid pill shapes unless a control is explicitly designed as a capsule.

## 5. Typography

- Use a neutral UI sans-serif family appropriate to the host application.
- Navigation labels: 13px compact and 14px comfortable, regular weight, single line with ellipsis.
- Space and section headings: same size as row labels, semibold.
- Supporting labels and metadata: 12–13px, secondary text color.
- Align text vertically within the row and use a compact line height.
- Do not use display typography, all-caps navigation, or oversized section titles in the shell.
- Density changes update row height, icon slot, spacing, and label size together.
- Icon-only controls require a programmatic accessible name; show a tooltip on hover or focus where the host supports it.

## 6. Application shell layout

The desktop shell has three regions: a narrow **Rail**, a resizable **Sidebar**, and a **Main area**.

```text
┌──────────┬──────────────────────────────┬──────────────────────────────┐
│ Rail     │ Sidebar                      │ Main area                    │
│ Spaces   │ Workspace switcher / heading │ Optional page header         │
│ Pins     │ Search, when appropriate      │ Optional page tabs / actions │
│ Shortcuts│ Sections and destinations     │ Content                      │
│ Profile  │ Persistent footer actions     │                              │
└──────────┴──────────────────────────────┴──────────────────────────────┘
```

- Rail width: 60px comfortable or 52px compact, including 12px outer margins.
- Combined Rail and Sidebar width: 272px default, resizable from 240px to 420px.
- Sidebar content scrolls independently. Keep the workspace heading and persistent footer actions reachable.
- Keep page-level actions outside the scrolling destination list.
- Where a horizontal application header is present, use a 52px band.
- In split views, preserve navigation row geometry and maintain a clear active context.

## 7. Sidebar component specifications

### Workspace switcher

Identifies the active workspace and opens the workspace menu.

- One navigation row high: 36px comfortable or 28px compact.
- Show a workspace mark in the standard icon slot, then a single-line semibold name and a disclosure affordance when interactive.
- The mark and name activate the same switcher.
- Open state uses the selected-row surface.
- Menu width: approximately 240px, with 6px outer padding and rows matching navigation row height.
- Menu rows contain a leading workspace mark, name, and clear selected state. Close the menu after selection.
- For long workspace lists, provide search at the top of the menu.
- Preserve the mark and disclosure affordance at narrow widths; truncate the name first.

### Section header and group

Groups related destinations under a compact, optionally collapsible heading.

- Header aligns to the same 10px leading inset as destination rows and uses 13–14px semibold text.
- Nested rows indent approximately 16px relative to the header while retaining the standard icon slot.
- Use a 9px disclosure icon for collapsed/expanded state. The full header hit area toggles the group when that is its primary action.
- An optional leading mark or badge may identify the group. Badges use the active workspace accent with accessible contrast.
- Optional trailing actions appear on hover and keyboard focus; they must remain keyboard reachable.
- A divider is a single hairline inset 10px on both sides. Use dividers only when grouping needs added separation.
- Do not place each group in its own card.

### Destination row

Used for selectable destinations that are not open browser tabs.

- Full-width hit target with 10px leading inset, 8–10px icon/label gap, and a fixed 15–16px icon slot.
- Label uses navigation typography, stays on one line, and truncates with ellipsis.
- Selected state: a soft neutral fill across the row, 8px compact or 10px comfortable corner radius, primary text and icon color.
- Hover state: a lighter, weaker neutral fill. Do not change font weight on hover.
- Optional badge or disclosure follows the label. Truncate the label before removing persistent controls.
- Optional remove action appears on hover or keyboard focus in a stable trailing slot. Do not shift the label when it appears.

### Open-tab row

Used for items representing open browser tabs and providing tab-specific actions.

- Match the destination row's height, icon slot, typography, insets, and selection treatment.
- Show the close action at the trailing edge on hover or keyboard focus, in a stable reserved slot.
- A site icon, favicon, or fallback mark occupies the leading icon slot.
- Optional status indicators must not alter row height or unexpectedly shift the title.

### Rail icon button

Used for compact navigation controls and utilities in the Rail or Sidebar toolbar.

- Square hit target: 36px comfortable or 28px compact; artwork around 14–16px.
- Icon color is muted at rest and primary on hover or selected.
- Selected uses the standard soft selection fill. Hover uses the weaker hover fill.
- Use an 8px corner radius. Do not show a border at rest.
- Show a visible keyboard focus ring with 1.5–2px thickness.

### Rail contents

- Use a vertical stack with 6px gaps and approximately 12px outer padding.
- Workspace marks use consistent 28–32px slots. The active workspace may use the selected fill; inactive marks remain quiet.
- Group pinned shortcuts together and separate them from workspaces with one inset divider.
- Keep persistent utilities such as downloads and profile access at the bottom.
- The primary create action sits near the top and opens a menu. Use a plus mark; while open, it may make a brief turn into a close mark.
- Overflow uses an ellipsis button with the standard rail button geometry.

### Sidebar search

- Reuse the application's established search control where one exists. Do not add a duplicate search field.
- Place navigation search below the workspace heading and above destination groups.
- Field height: 28–32px, 8px radius, compact UI typography, leading search icon, and a clear action only when the query is nonempty.
- Search in a temporary menu may receive focus on open and clear on close or selection. Persistent page filters retain their query according to the page's own behavior.

### Footer actions

- Keep persistent utility actions at the bottom of the Sidebar or Rail, outside the scrolling destination list.
- Align them to the same insets and icon button geometry as the rest of navigation.
- Separate with spacing or one hairline; avoid a heavy footer border.

## 8. Horizontal application header and tabs

Use a shared horizontal header where the application context has a switcher, page/tool tabs, and fixed actions.

- Header band: 52px high; tab control: 28px high; 2px between tabs.
- Order: context switcher, thin divider, horizontally scrollable tabs, fixed actions.
- Only the tab list scrolls. Keep the switcher and fixed actions visible.
- Tabs use a leading mark, single-line label, and the same hover/selected surfaces as navigation rows.
- Selected tabs use a soft neutral fill. Do not use underlines or heavy borders.
- Maximum tab width: approximately 186px. At narrow widths, truncate titles before reducing the icon slot; allow horizontal scrolling.
- Do not duplicate a header when an embedded workspace already supplies its own application chrome.

## 9. Interaction states and accessibility

| State | Surface | Content |
| --- | --- | --- |
| Rest | Transparent or inherited surface | Muted for secondary controls; primary for current context |
| Hover | Low-opacity neutral fill | Primary text and icon |
| Selected | Stronger soft neutral fill | Primary text and icon |
| Keyboard focus | Existing state plus visible focus ring | Existing state colors |
| Pressed | Slightly stronger fill or brief scale/opacity response | Primary text and icon |
| Disabled | No hover fill; reduced but readable contrast | Muted text and icon |
| Destructive | No persistent red surface | Semantic red on action or icon |

- Focus and hover are distinct. Keyboard focus remains visible without pointer hover.
- Focus rings follow component corners and do not change layout.
- Entire destination rows are clickable. Nested actions have separate hit targets and accessible names.
- Menus support standard keyboard navigation, activation, and dismissal.
- Use short transitions around 140ms for hover and selection. Respect reduced-motion preferences.
- Avoid animating ordinary row geometry in ways that shift adjacent labels.

## 10. Token adaptation

The semantic token names shown above are an optional mapping aid. Preserve the host project's existing naming, color format, font conventions, and component primitives. Map equivalent roles rather than introducing a second token system. A density preference should update row height, icon size, spacing, and label size as a coordinated set.

