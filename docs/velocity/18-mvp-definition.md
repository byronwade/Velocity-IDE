# Velocity MVP Definition

Ship a **usable daily-driver core** beside the VS Code fork — not feature parity, not Monaco, not plugins.

## In scope (this MVP)

| Capability | Bar |
|---|---|
| Open workspace | Open a real folder path (fixture + typed path). OS dialog when Runtime hook exists. |
| File tree | Bounded scan; skip `node_modules` / `.git` / vendor. |
| Edit file | Native `<textarea>` bound to document buffer (dirty tracking). |
| Save file | Write active document back to disk (Cmd/Ctrl+S / command palette). |
| Command palette | Open Folder, Save, Toggle Terminal, theme, safe mode. |
| Terminal | Pipe-based shell command runner via Process Governor + `fx.spawn` (not full PTY). |
| Agent panel | Local task board only — no network AI. |
| Telemetry | Off. |

## Explicitly out of MVP

- Monaco / rich editor island
- Real PTY / interactive shell
- LSP / Git / Debug / Search index
- Plugin downloads / marketplace
- OS folder dialog (stretch; path entry ships first)
- Electron workbench changes

## Success criteria

1. `native check` / `test` / `build` pass
2. Open fixture → edit → save → re-open shows change
3. Run a shell command in terminal panel; output streams; governor tracks it
4. First paint stays free of plugins/LSP/git/terminal spawn
