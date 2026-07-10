# Precision Workbench — design language

Velocity's target design language is the **Precision Workbench**: a compact,
command-first, information-dense, icon-led, keyboard-first, dockable desktop
workbench with quiet chrome and task-specific layout perspectives. Velocity
should read as a precision professional instrument — closer to a serious
developer/creative tool than to a website placed inside a native window.

This document is the authoritative statement of the design language. The
companion documents are:

- [`workbench-surface-audit.md`](./workbench-surface-audit.md) — baseline
  inventory of every surface, control, and defect.
- [`control-command-inventory.md`](./control-command-inventory.md) — the
  command-to-control mapping and the icon-only-vs-labeled rules.
- [`layout-contract.md`](./layout-contract.md) — the native layout model,
  panel registry, presets, persistence, and keyboard contract.

## Governing principles

1. Minimal chrome, not minimal capability.
2. Dense, not cramped.
3. Quiet, not cryptic.
4. Content-first, not decoration-first.
5. Commands before buttons.
6. Stable spatial organization before visual novelty.
7. Progressive disclosure instead of permanent clutter.
8. One cohesive workbench instead of independent cards and pages.

## What Velocity must not resemble

A SaaS dashboard, a marketing site, a collection of cards, a component-library
demo, a widened mobile UI, a browser page in a native window, a bubbly
rounded-rectangle interface, a toolbar where every icon repeats itself in text,
unrelated-looking panels, mouse-only customization, a fake docking system, a
"minimal" UI that hides necessary functionality, icon soup, or a responsive
web-breakpoint system pretending to be desktop layout behavior.

## Stable region map

The shell exposes stable landmark regions. Individual tools may move between
supported regions, but the landmarks themselves are fixed and the editor is
always the visual center of gravity.

```
┌───────────────────────────────────────────────────────────────┐
│ Titlebar / command area (window-drag, palette entry)           │  header
├──┬───────────────┬──────────────────────────────┬─────────────┤
│  │               │  Editor tab strip · layout    │             │
│A │  Primary      │  chrome (panel-left,          │  Secondary  │
│c │  sidebar      │  panel-right, ⋯ Customize      │  sidebar    │
│t │  (Explorer /  │  Layout)                       │  (Agent)    │
│i │  Search /     ├──────────────────────────────┤             │
│v │  SCM /        │  Breadcrumb / editor toolbar  │             │
│i │  Outline)     ├──────────────────────────────┤             │
│t │               │                              │             │
│y │               │  Editor group (center of      │             │
│  │               │  gravity, edge-to-edge)       │             │
│  ├───────────────┴──────────────────────────────┤             │
│  │  Bottom panel (Terminal / Output / Problems)  │             │
├──┴───────────────────────────────────────────────┴─────────────┤
│ Status bar (branch · language · doc stats · dirty)             │
└───────────────────────────────────────────────────────────────┘
Floating overlays: command palette, quick open, symbol palette,
notifications, diff review, snippet picker, keyboard shortcuts,
Customize Layout menu.
```

Region ownership is enforced by the shell (`apps/native-shell/src/app.native`)
and the TEA model (`src/model/app_model.zig`). Opening one panel never
relocates an unrelated panel; presets change only the visibility of the
landmark regions.

## Density system

Compact is the primary target; a Comfortable option is a future addition. The
current dimensions (px) live in the markup and `theme/tokens.zig`:

| Element | Target | Notes |
|---|---|---|
| Titlebar / command area | 34–38 | `header_natural_height = 36`, grows only for OS inset |
| Activity rail | 40–46 | `width="46"` |
| Editor tab strip | 30–34 | `size="sm"` ghost buttons, `padding="4"` |
| Panel header | 28–32 | `size="sm"` header rows |
| Breadcrumb / editor toolbar | 26–30 | `padding="6"` row |
| Tree / compact list rows | 24–28 | `padding="4"` list items |
| Status bar | 20–24 | `status-bar` element |
| Common icons | 14–16 | `width="13–15"` |
| Toolbar gaps | 2–4 | `gap="2".."4"` |
| Panel-header horizontal padding | 6–8 | `padding="6"` |

Spacing scale: **2, 4, 6, 8, 12, 16, 24**.

### Radius policy (`theme/tokens.zig`)

Large radii are deliberately avoided in the permanent workbench so the chrome
reads as one integrated instrument, not a set of bubbly cards.

| Surface | Radius |
|---|---|
| Docked workbench panes | 0 px (background fills, no exterior radius) |
| Compact controls (`sm`) | 3 px |
| Fields / menus (`md`) | 5 px |
| Cards / groups (`lg`) | 6 px |
| Floating dialogs / overlays (`xl`) | 8 px |

Previously the tokens used `sm=4, md=7, lg=11, xl=15`, which produced the
bubbly, low-density feel and made the editor read as a floating rounded card.
The new values (`sm=3, md=5, lg=6, xl=8`) keep controls modern without drifting
away from a precision-instrument density.

## Docked vs floating geometry

A surface is either **docked** or **floating** and must never visually mix both
models.

- **Docked** surfaces sit flush in the workbench grid, use zero exterior corner
  radius, share hairline separators, align with neighbouring pane boundaries,
  and carry no independent shadow or exterior margin. The editor, sidebars,
  bottom panel, activity rail, and status bar are docked.
- **Floating / intentionally inset** surfaces (command palette, Customize Layout
  menu, notifications, diff review) have deliberate surrounding space, a
  restrained radius, subtle elevation, and correct focus/dismissal behaviour.

The editor is integrated **edge-to-edge**: its outer card padding was removed,
its tab strip / breadcrumb / content are separated by shared hairline
`<separator />` dividers rather than by exterior margins, and its rounding is
gone (radius 0 for docked panes). See the surface audit for before/after.

## Icon grammar

One icon family, one optical grid — the built-in set in
`canvas.icons.known_icon_names`. No emoji, no mixed stroke weights, no
outline/filled mixing without semantic reason. A given icon keeps one stable
meaning across the whole application:

| Icon | Meaning |
|---|---|
| `plus` | create / add in the current context |
| `x` | close / dismiss |
| `chevron-*` | disclose / expand / collapse / navigate by direction |
| `search` | search |
| `panel-left` | primary sidebar |
| `panel-right` | secondary sidebar |
| `ellipsis` | more actions / Customize Layout menu |
| `refresh-cw` | refresh / reset |
| `repeat` | rerun / restore-previous |
| `play` | run |
| `x-circle` | stop |
| `trash` | delete / clear |
| `save` | save |
| `settings` | application settings |

Icon-first never means unnamed: every icon-only control carries an accessible
name (`label=`), and — where a shortcut exists — the tooltip states it. Text is
retained where the action is a surface's primary purpose, the glyph is
ambiguous, the action is rare/consequential/destructive, or adjacent icons
would be hard to distinguish (Stage/Unstage/Restore, Commit, Definition,
Append Snippet, Preview/Apply, Run Profile, and the named layout perspectives
all keep text).

## Progressive disclosure

A panel keeps its 1–3 most frequent commands visible; the rest live in ellipsis
menus, context menus, the command palette, and keyboard shortcuts. Hover-only
actions are never the only path and never shift row content. The root
application never scrolls like a website — each major pane owns its own scroll
container and headers stay fixed.
