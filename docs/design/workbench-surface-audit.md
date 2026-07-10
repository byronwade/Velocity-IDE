# Workbench surface audit

Baseline inventory of the Velocity shell as of the Precision Workbench pass,
plus the defects found and their resolution. The shell is a single declarative
document, `apps/native-shell/src/app.native`, projected from the TEA model in
`src/model/app_model.zig`.

## Environment note (honest baseline)

The refinement was performed in an execution environment that **cannot compile
or launch the application**: the pinned Zig toolchain download
(`ziglang.org`) is blocked by egress policy (HTTP 403) and GTK 4 / WebKitGTK 6
are not installed. Consequently:

- `native markup check --strict` **was** run against every template change and
  passes (`src/app.native: ok`).
- `native test`, `native build`, `native check --strict`, and the eight smoke
  suites **could not** be run here, and no live screenshots could be captured.
- All Zig changes were made additively by mirroring existing, test-covered
  patterns exactly (constant-payload fields like `project_acme`, the
  `run_command` string-dispatch chain, the `dismissOverlay` overlay chain, and
  the `view_unbound` binding contract). They are described below and must be
  validated with `npm run check` in a Zig-capable environment before release.

## Region / surface inventory

| Region | Element | Source |
|---|---|---|
| Header | Titlebar with window-drag + command-palette entry | `app.native` header row |
| Activity rail | Explorer, Search, SCM, Outline, Problems, Agents, Terminal, Settings icon buttons | rail column |
| Primary sidebar | Explorer tree, Search+Replace, Source Control, Outline | left column `<if>` blocks |
| Editor region | Tab strip, layout chrome, breadcrumb toolbar, find/replace, peek, textarea | center column |
| Secondary sidebar | Agent composer + task list | right column `showAgentChrome` |
| Bottom panel | Terminal / Run profiles / Tasks, Output channels, Problems | `showBottomPanel` column |
| Status bar | branch · language · doc stats · dirty | `status-bar` |
| Overlays | Command palette, Quick Open, Symbol palette, Notifications, Diff review, Snippet picker, Shortcuts, **Customize Layout (new)** | stack-root `<if>` blocks |
| Full-page views | Settings, Plugins, Feature matrix, Process governor, Debug, Testing, Perf HUD | center column `<if>` blocks |

Scroll containers (each an intentional single owner): file explorer, search
results, replace preview, git changes, outline, agent tasks, terminal output,
output log, problems list, settings sections, notifications, diff lines,
snippet list, quick-open results, symbol results, shortcuts list, perf metrics.

Every visible action traces to a model message (`Msg` union) and, for
palette-exposed actions, to `core/command_registry.zig`. Keybindings live in
`core/keybinding_registry.zig`.

## Defects identified

1. **Rounded editor pressed against borders (flagged).** The editor content was
   wrapped in a card with `padding="8"` (outer) + `padding="6"` (inner) and,
   combined with the old large radius tokens (`sm=4…xl=15`), read as a floating
   rounded card incorrectly docked flush against the sidebar and bottom-panel
   borders — the exact hybrid the design language forbids.
2. **Bubbly radius across permanent chrome.** Large radii (`lg=11, xl=15`) on
   docked panes gave a low-density, non-instrument feel.
3. **Redundant text beside universal icons.** Back/Forward buttons paired
   `chevron-left`/`chevron-right` with the words "Back"/"Forward"; the agent
   toggle paired `send` with a dynamic label.
4. **No layout customization surface.** There was no Customize Layout control,
   no named perspectives, and no keyboard/menu path to rearrange regions
   atomically — only individual toggles.
5. **Icon meaning drift risk.** The activity rail used `menu` for Outline and
   `send` for Agents; adding more controls risked reusing those glyphs with new
   meanings.

## Resolutions applied

| Defect | Resolution |
|---|---|
| 1 | Removed the editor's outer/inner card padding; the editor column is now `gap="0"` with shared `<separator />` dividers between tab strip, breadcrumb toolbar, and content — integrated edge-to-edge. Find/replace rows got their own `padding="6"` so they no longer relied on the removed card margin. |
| 2 | Radius tokens retuned to `sm=3, md=5, lg=6, xl=8`; docked panes render at 0 radius. |
| 3 | Back/Forward are now icon-only (`chevron-left`/`chevron-right`) with their existing accessible names; the agent toggle became an icon-only `panel-right` region control. |
| 4 | Added an upper-right **Customize Layout** control (`ellipsis`, tooltip "Customize Layout") opening a keyboard-accessible menu with five perspectives (Coding, Focus, Review, Debug, Terminal), Save Current as Custom, Restore Previous Layout, Reset Layout, and live region toggles. All routes go through the canonical `run_command` path and appear in the command palette. |
| 5 | New controls use distinct, semantically stable glyphs: `panel-left` (primary sidebar), `panel-right` (secondary sidebar), `ellipsis` (layout/more). No glyph carries two meanings in the editor chrome. |

Two further defects were found during the CI screenshot tour (headless GTK)
and fixed:

6. **Editor toolbar collided at the minimum window size.** The breadcrumb
   toolbar carried too many text buttons. Go to File, Append Snippet, and
   Restore Backup now collapse into an ellipsis "More editor actions" overflow;
   only back/forward, breadcrumb, go-to-symbol, and Save remain in the compact
   bar (progressive disclosure).
7. **Performance HUD could not be dismissed and overlapped the bottom panel.**
   `show_perf_hud` was only ever set true — there was no close affordance, so
   once opened the 360 px HUD permanently occupied the editor column and, with
   the 280 px bottom panel also open, over-subscribed the vertical space and the
   editor toolbar overlapped the panel below. Added a close control on the HUD
   header (`close_perf_hud`) and made the HUD and the bottom panel mutually
   exclusive (opening either closes the other), so the two can never overlap.

## Not yet addressed (tracked for follow-up)

- True editor-group **splitting** and moving editors between groups (the model
  currently has a single editor group). The layout schema in
  [`layout-contract.md`](./layout-contract.md) specifies the split-tree; the
  runtime split UI is a follow-up phase.
- **Drag-and-drop** docking. Per the design language, menu/command/keyboard
  movement is provided first; DnD is deferred until it can be real, not faked.
- **Virtualized** file-tree / large-list rendering is bounded by the existing
  scanner caps; explicit windowed virtualization is a follow-up.
- Live visual QA (screenshots, minimum-window wrap test, theme sweeps) requires
  a Zig+GTK environment and is pending.
