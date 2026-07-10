# Layout contract

The native, UI-independent, versioned layout model for the Precision Workbench.
This document specifies the full model and records what is implemented today
versus what is specified for follow-up phases.

## Implemented today (`src/model/app_model.zig`)

The current shell uses a **bounded region-visibility model** — the region
landmarks (primary sidebar, editor, secondary sidebar, bottom panel) plus which
tool occupies the primary sidebar and bottom panel. This is enough to deliver
working, persistent layout perspectives without a speculative split-tree UI.

### `LayoutSnapshot`

A constant-size snapshot of region visibility — proportional to the number of
landmarks, never to file/search/terminal content, so capture and restore are
O(1):

```zig
pub const LayoutSnapshot = struct {
    show_sidebar: bool = true,
    show_agent_panel: bool = false,      // secondary sidebar
    bottom_panel_open: bool = false,
    focus_mode: bool = false,
    selected_activity: Activity = .explorer,
    bottom_panel_tab: BottomPanelTab = .terminal,
};
```

### `LayoutPreset`

```zig
pub const LayoutPreset = enum { coding, focus, review, debug, terminal, custom };
```

### Operations

| Operation | Function | Notes |
|---|---|---|
| Apply preset | `applyLayoutPreset` | Captures `prev_layout`, sets `active_layout_preset`, applies `presetSnapshot`, persists |
| Apply snapshot | `applyLayoutSnapshot` | Sets region fields; opens bottom panel via `openBottomPanel`; persists |
| Capture | `captureLayout` | O(1) snapshot of the six landmark fields |
| Save custom | `saveCustomLayout` | Snapshot current regions into `custom_layout` |
| Restore previous | `restorePreviousLayout` | Swap current ↔ `prev_layout` |
| Reset | (`reset_layout`) | Apply the Coding default |

### Persistence and recovery

Region visibility persists through the existing `prefs` store
(`persistPrefs` writes `show_sidebar`, `show_agent`, `bottom_panel_open`,
`bottom_panel_tab`, `focus_mode`, …). Because presets set exactly these fields,
a preset's resulting layout survives a restart. Missing/corrupted prefs already
fall back to safe defaults in `prefs.zig`, so a preset can never restore a panel
into a zero-width or off-screen state — visibility is boolean and the region
geometry is fixed by the shell.

### Preset semantics

| Preset | Sidebar | Activity | Bottom panel | Secondary | Focus |
|---|---|---|---|---|---|
| Coding | on | Explorer | hidden | hidden | off |
| Focus | off | — | hidden | hidden | on |
| Review | on | Source Control | Problems | hidden | off |
| Debug | on | Explorer | Terminal | hidden | off |
| Terminal | off | — | Terminal (enlarged) | hidden | off |
| Custom | last saved snapshot | | | | |

Applying a preset changes **presentation only**. Open files, unsaved buffers,
running terminals/tasks, and navigation state are untouched — the operations
mutate only the six visibility fields and never open/close documents or spawn
processes.

## Specified for follow-up: full `LayoutState` schema

The region-visibility model is the first slice of a versioned split-tree layout
model. The full schema (to be implemented when editor-group splitting lands) is:

```
LayoutState
  schema_version : u32
  active_preset  : LayoutPreset
  previous_layout: ?LayoutState
  primary_sidebar / secondary_sidebar / bottom_panel : Node
  central_editor_grid : Node
  focus_path : []NodeId
  saved_dimensions / saved_split_ratios : bounded map
  panel_groups : []Stack

Node = Split | Stack | Panel | EditorGroup
  Split       { axis: h|v, ratio: clamped f32, min_sizes, a: Node, b: Node }
  Stack       { panel_ids: []PanelId, active: PanelId }
  Panel       { id: PanelId }
  EditorGroup { editor_ids: []EditorId, active: EditorId, locked: bool }
```

Requirements the schema must meet: versioned, validated, migratable,
recoverable, bounded, resilient to missing panels and corrupted state,
resettable, and scoped to user/profile/workspace. Layout operations must be
proportional to the number of layout nodes, not to content. Continuous resize is
not animated; split ratios are clamped to valid minimums; a panel is never
restored to a zero-width or off-screen state.

## Panel registry (specified)

Every panel is declared once through a coherent registry rather than hardcoded
in the shell. Each declaration carries: stable id, title, icon, accessible
name, purpose, feature owner, default/allowed regions, default/min/max size,
closable/movable/resizable/duplicable/groupable/editor-region flags, lazy-mount
and suspend policy, visibility/focus/move/maximize/restore command ids, keyboard
shortcut, persistence policy, and availability conditions. The current shell
enumerates panels inline; extracting the registry is the next structural step,
and the `Activity` enum plus `command_registry.zig` are the seams for it.

## Panel anatomy (contract)

Every panel has one responsibility and the same anatomy: a compact header
(identity left, 1–3 frequent actions right, overflow in an ellipsis menu), one
intentional content region, one scroll owner, visible focus, predictable
resize/close behaviour, and explicit empty/error/loading/unavailable states.
Panel headers align across neighbouring regions; a title is never repeated in
nested headers.

## Keyboard contract

Implemented: Escape dismissal priority (Customize Layout menu closes first when
open), plus the region-toggle chords (Cmd+B / Cmd+J / Cmd+Shift+A) surfaced as
labeled shortcuts inside the Customize Layout menu.

Specified for follow-up: focus-primary/secondary/bottom/editor commands,
focus-next/previous group, focus-group directional, move-focused-panel,
move-active-editor-between-groups, split-editor directional, keyboard split
resize, maximize/restore, cycle-panel-tabs, and apply/save/reset/restore-layout
chords — all with platform-aware modifiers, user rebinding, chords, `when`
clauses, conflict detection, and a keyboard-shortcut editor.

## Drag-and-drop policy

Drag-and-drop is not shipped. Per the design language, no essential layout
operation is drag-only: movement is provided first via menu, command palette,
and keyboard. Draggable handles will be added only when the Native SDK can back
real dragging — Velocity does not ship fake drag affordances.
