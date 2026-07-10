# Velocity UI Audit

A design audit for migrating Velocity's native shell to Cursor-desktop quality
while keeping an original, editor-first, pre-AI identity. Sources: a read-only
archaeology pass over `apps/native-shell/` and web research on the current
Cursor desktop interface (2025-2026). Cursor primary pages 403 to automated
fetch, so Cursor claims rest on search synthesis + established VS Code
conventions (Cursor is a VS Code fork); those are marked below.

## What Cursor / VS Code does well (adapt)

- **Warm-neutral dark identity with one restrained accent.** Cursor leans warm
  minimalism (warm dark base, single brand accent). Adopt the *approach* with
  Velocity's own amber signal — never Cursor Orange `#f54e00` or its gold.
- **VS Code chrome geometry** (the fork's native baseline): ~48px icon-first
  left rail, ~35px tabs (28px compact), ~22px breadcrumb + status bar,
  top-anchored ~600px command palette with right-aligned shortcut hints.
- **Flat rectangular tabs**, not buttons: active = editor-background fill + a
  1-2px top accent; dirty = a filled dot that swaps to × on hover.
- **Uppercase small-caps section headers** (~11px) with hover-revealed context
  actions, rather than large bold titles.
- **Top-anchored Quick Input** (palette/quick-open drop from the titlebar
  region), horizontally centered.
- **Density controls** and **named layout presets** as a mechanism (Editor /
  Zen / Focus) — Velocity already has focus mode + panel toggles to build on.

## What NOT to copy

- **Agent-first reorganization** (Cursor 2.0/3.0 organizes work around agents
  and demotes the editor/file tree). Velocity is editor-first and pre-AI; the
  local task board stays closed by default and visually subordinate.
- **Right-side agent panel as the primary surface**; **Agent Tabs / multi-agent
  grid**; the **"Glass layout"** secondary-sidebar replacement (it made
  extensions vanish).
- **Proprietary trade dress**: Cursor Orange/gold, logo/wordmark, named themes
  (Twilight Gray, Warm Sand), proprietary font, CSS.

## Documented Cursor usability complaints to avoid

- Editor hidden behind chat; primary navigation/controls removed or relocated
  without warning (forum megathread t/146790, t/139840).
- Layout breakage on ultrawide / stacked monitors (the-decoder, HN).
- Status bar disappearing after updates; wrong Git branch shown (cursor/cursor
  #3874, forum t/145954, t/159062). Keep the status bar reliable and accurate.
- Redundant/agent-labeled navigation and inconsistent sidebar position.

## Current Velocity inconsistencies (from archaeology)

Line refs are `app.native` unless noted.

1. **Bubbly radii** — `tokens.zig` had `lg=11, xl=15`; cards/overlays inherit
   `lg`/`xl` and read round. (Fixed in this migration: `sm4/md6/lg8/xl8`.)
2. **Settings header carries an extra element** — `{app_version_label}` is
   pinned in the header (line 518) and there is **no explicit Back button**
   (returning to launch is buried at the bottom of the About section).
3. **Implicit chrome heights** — tab strip, breadcrumb, and status bar set no
   explicit height; they inherit from `sm` buttons + `padding=4` and drift out
   of the 32-36 / 26-30 / 20-24 density bands.
4. **Duplicated controls** — case/whole-word toggles live in both the Search
   panel (104-105) and Settings→Workspace (556-557); `restore_backup` appears
   in 3 places (breadcrumb 235, disk-conflict 244, backup-status 252);
   `{problemsStatus}` renders twice in the Problems path; two Notifications
   entries in Settings (573, 597); "Refresh Performance Metrics" is triplicated.
5. **Overflow at 960×640** — diff-review modal is `920×660` (line 710), taller
   than a 640px viewport before its `padding=48` scrim; notifications
   `760×560`+scrim also exceed 640.
6. **Missing ellipsis** on hard-clipping chrome text — tab titles (212),
   breadcrumb segments (226), titlebar "Velocity" (8), agent task title (298).
7. **Oversized persistent editor toolbar** — breadcrumb row carries
   go-to-symbol / Go to / Snippet / Backup / a large primary Save; all are
   available via palette/shortcuts and crowd the editor header.

## Proposed implementation mapping (surface → files)

| Surface | Change | Files |
|---|---|---|
| Global density/radii/type | compact tokens (radii 4-8, body 13/label 12, heights 26/30/34) | `theme/tokens.zig` |
| Titlebar | quiet, keep native inset + drag; ellipsis on title | `app.native` |
| Activity rail | keep icon-first ~46px; tighten padding; single active accent | `app.native` |
| Tab strip | pin ~34px; ellipsis tab titles; nav stays here | `app.native` |
| Breadcrumb/editor header | pin ~28px; strip nonessential commands, drop persistent Save | `app.native` |
| Status bar | keep segments; verify ~22px band | `app.native` |
| Bottom panel | consistent compact header; de-dupe status badge | `app.native` |
| Settings | full-page; **Back+title header only**; Developer section for Feature Matrix/Governor/Perf/Plugins; de-dupe toggles; centered ~760px | `app.native`, `app_model.zig` |
| Palette/Quick/Symbol | top-anchored ~620px cards over scrim | `app.native` |
| Modals (diff/notifications/snippet/shortcuts) | clamp to fit 960×640 | `app.native` |

## Must-preserve (do not break)

TEA model + `update` switch; Process Governor wiring; command/keybinding/feature
registries and their compile-time invariants; bounded fixed-size state; the
save-conflict surface (`showDiskConflict` / `overwrite_file` "Keep Mine" /
backup restore); both `view_unbound` lists (strict check); and the exact
visible strings / accessible labels asserted by `src/tests.zig` and
`scripts/*.sh` (e.g. "Open Folder", "Back", "Forward", "Whole Word",
"Keyboard Shortcuts", "Notification History", "Velocity", "Accessibility",
"No settings found", "Application settings", "Change color theme",
"Toggle integrated terminal", "Command search", "Terminal command",
"Stop Terminal/Task", "Run Selected Task", "Close Diff Review", and the
perf-value regexes).
