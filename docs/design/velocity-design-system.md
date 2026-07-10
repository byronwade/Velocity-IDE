# Velocity Design System

The single source of visual truth for the Velocity native shell. Compact,
editor-first desktop density inspired by Cursor/VS Code quality, expressed
through the Native SDK `DesignTokens` and disciplined `.native` markup. Original
identity — no third-party brand assets.

Implemented in `apps/native-shell/src/theme/tokens.zig`; applied in
`apps/native-shell/src/app.native`.

## Principles

- Desktop-first, editor-first: the editor is the visual center of gravity.
- Quiet, precise, warm, calm. Legibility over decoration.
- Hierarchy from weight, opacity, and spacing — not giant text.
- Hairline structure; shadows only on floating surfaces.
- Nothing bubbly: tight radii everywhere in the workbench.
- Never overflow the window; every region has one intentional scroll owner.

## Color (warm-neutral, single amber accent)

Warm stone/sand neutrals, never pure black/white, never cool zinc. One
restrained amber signal for focus/selection. Full ramps in `tokens.zig`
(`dark_colors` / `light_colors`); high-contrast uses the SDK house pack.

| Intent | Dark | Light |
|---|---|---|
| background (ink / paper) | `#0D0C0B` | `#FAF9F6` |
| surface | `#14120F` | `#FFFFFD` |
| surface subtle | `#1C1917` | `#F4F2ED` |
| text | `#F7F4EF` | `#1C1916` |
| text muted | `#978F85` | `#7A7268` |
| border | warm white ~8% | `#E8E3DA` |
| accent (mono primary) | `#F6F3EE` | `#1C1916` |
| focus / selection (amber) | `#DBAA6C` | `#C69254` |
| info / warn / ok / danger | `#7EA4F4` / `#E09E52` / `#4EBE82` / `#E95C4E` | `#2C62D6` / `#BE7A26` / `#1C9462` / `#CE4438` |

## Radii (tight, non-bubbly)

`sm 4` compact controls · `md 6` fields/menus · `lg 8` cards/floating surfaces ·
`xl 8` dialogs. Nothing in the chrome exceeds 8px.

## Typography

System sans (SDK house face; not Cursor's proprietary font) + house monospace
for editor/terminal. Sizes: **body 13**, **label 12**, **button 13**,
**title 16**, heading 20, display 30. Section headers render as muted small
captions, not oversized titles.

## Spacing

Compact scale used in markup padding/gap: **2 · 4 · 6 · 8 · 12 · 16 · 24**.
SDK `spacing` tokens (xs4/sm8/md12/lg16/xl24) drive default control insets and
are left at house values; density is expressed through markup padding.

## Control metrics

One compact height register: **sm 26 / default 30 / lg 34** (SDK
`ControlMetricTokens`). Toolbar rows compose from same-size controls so a row
lands on one tight height.

## Density bands (chrome heights)

| Region | Target | Velocity |
|---|---|---|
| Titlebar | 34-38 | `header_natural_height` 36 |
| Activity rail | 42-46 | width 46, icon-first |
| Tab strip | 32-36 | pinned 34 |
| Breadcrumb/editor header | 26-30 | pinned 28 |
| Status bar | 20-24 | SDK `status-bar` default |
| Common controls | 26-30 | `size="sm"` = 26 |
| Sidebar | 250-280 | 260 (range 220-420) |
| Right panel | 300-380 | agent panel 300, closed by default |
| Command palette | 560-640 | 620, top-anchored |
| Settings content | 720-840 max | 760 centered |

## Elevation & motion

Shadows: SDK `shadow.xs/sm/md` — only palettes, menus, dialogs, and detached
overlays carry elevation; docked chrome stays flat with hairline borders.
Motion: SDK `motion` tokens honor reduced-motion; prefer opacity + small
translation, 80-140ms; never delay an action for animation.

## Interaction states

Every interactive surface must read correctly in: default, hover, pressed,
selected, focus-visible, disabled, warning, destructive, empty, long-content,
constrained-window, keyboard-only, reduced-motion, high-contrast. Selection
uses the amber signal; focus is a 1px accent ring; hover is a subtle
background lift (SDK `states` tokens).

## Overflow contract

Root is window-constrained. Every flex/grow container may shrink. Toolbars,
tab strip, breadcrumb, activity rail, and status bar never wrap — long labels
truncate (`overflow="ellipsis"`) or collapse to icon-only; optional metadata
disappears before essential actions. Modals are sized to fit the declared
minimum window (960×640): card + scrim padding must total ≤ window height. No
horizontal scrolling in chrome; no fake responsive breakpoints.

## Native SDK notes / limitations

- Overlays center via a scrim `column` + `card` (the markup `dialog` element
  renders in place in the reference renderer, so it is not used for centered
  modals).
- Built-in vector icons only (compile-checked set); no custom icon fonts.
- Editor is a native `<textarea>` (no gutter/decoration/caret API yet) — line
  numbers and inline decorations are out of scope until the editor island lands.
- Status-bar height is SDK-default; not independently themable today.
