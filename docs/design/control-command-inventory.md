# Control / command inventory

Every meaningful action has one canonical command. Icon buttons, labeled
buttons, menus, the command palette, and keyboard shortcuts all invoke the same
model path. There is no separate mouse-only or keyboard-only behaviour.

## Command path

```
markup on-press ─┐
command palette ─┼─► Msg (app_model.zig) ─► updateInner switch ─► model mutation
keyboard chord ──┘        ▲
                          │
core/keybinding_registry.zig ─(onCommand)─► Msg
core/command_registry.zig  ─(palette projection: model.commands)
```

- `core/command_registry.zig` — authoritative palette metadata (id, title,
  hint, availability, feature owner, dispatch coverage). `model.commands` is a
  direct projection of `command_registry.palette`.
- `core/keybinding_registry.zig` — authoritative shortcut records; `onCommand`
  maps a shortcut id to its canonical `Msg`.
- Multi-target actions that need a literal argument in markup expose a
  constant-payload field on the model (literals are disallowed in on-press
  bindings), e.g. `project_acme`, and the new `layout_cmd_*` fields.

Tests enforce the coupling: unique command ids, dispatch coverage, every
advertised shortcut matches its canonical binding, every command `feature_id`
exists in the feature registry, and `palette.len == model.commands.len`.

## Icon-only vs labeled decision table

| Presentation | When | Examples |
|---|---|---|
| Icon-only (accessible name + tooltip, shortcut in tooltip) | Compact, repeated, universally recognizable | close `x`, refresh `refresh-cw`, add `plus`, navigate `chevron-*`, search `search`, sidebar toggles `panel-left`/`panel-right`, Customize Layout `ellipsis` |
| Icon + label | Surface's primary purpose, or ambiguous/consequential glyph | Save, Run Profile, Commit, Definition, Append Snippet |
| Label only | Named choice where a glyph would add nothing | layout perspectives (Coding/Focus/Review/Debug/Terminal), Preview/Apply Replace, Stage/Unstage/Restore |

Icon-first never means unnamed — every icon-only control has a `label=`
accessible name, and controls with a bound shortcut state it in the tooltip
(e.g. "Toggle Primary Sidebar (Cmd+B)").

## Layout commands (added in this pass)

Canonical commands registered in `command_registry.zig`, dispatched in the
`run_command` handler, and reachable from the command palette, the Customize
Layout menu, and (for region toggles) existing keyboard chords:

| Command id | Title | Behaviour |
|---|---|---|
| `layout_preset_coding` | Layout: Coding Preset | Explorer + dominant editor; bottom/secondary hidden |
| `layout_preset_focus` | Layout: Focus Preset | Editor only, minimal chrome |
| `layout_preset_review` | Layout: Review Preset | Source Control + editor + Problems |
| `layout_preset_debug` | Layout: Debug Preset | Explorer + editor + terminal/console |
| `layout_preset_terminal` | Layout: Terminal Preset | Editor + enlarged terminal, others hidden |
| `save_layout_custom` | Layout: Save Current as Custom | Snapshot current regions into the Custom perspective |
| `restore_previous_layout` | Layout: Restore Previous | Swap to the pre-preset layout |
| `reset_layout` | Layout: Reset to Default | Apply the Coding default |
| `open_layout_menu` / `close_layout_menu` | (menu plumbing) | Toggle the Customize Layout overlay |

These commands carry no `feature_id` and no shortcut hint, so they satisfy the
registry coupling tests without touching the feature catalog or keybinding
registry. Region toggles reuse the existing `toggle_sidebar` (Cmd+B),
`toggle_bottom_panel` (Cmd+J), and `toggle_agent` (Cmd+Shift+A) commands.

## Keyboard baseline (existing, preserved)

VS Code / Cursor muscle memory is preserved via `keybinding_registry.zig`:
Cmd/Ctrl+P (Quick Open), Cmd/Ctrl+K (Command Palette entry — Velocity uses K for
the palette; Shift+P is available as an alias target), Cmd/Ctrl+B (sidebar),
Cmd/Ctrl+J (bottom panel), Ctrl+` (terminal), Cmd/Ctrl+, (settings), Cmd/Ctrl+W
(close editor), Cmd/Ctrl+Shift+T (reopen closed), Cmd/Ctrl+F (find),
Cmd/Ctrl+Shift+F (workspace search), Cmd/Ctrl+Shift+O (symbol), Cmd/Ctrl+Shift+A
(agent/secondary sidebar), plus Escape overlay dismissal priority (the
Customize Layout menu is inserted early in `dismissOverlay` so Escape closes it
predictably).

Follow-up keyboard work specified in [`layout-contract.md`](./layout-contract.md):
focus-region commands, move-panel commands, split/maximize/restore chords, and a
user-facing keybinding editor.
