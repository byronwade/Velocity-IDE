# Velocity MVP Definition

Ship a **usable daily-driver core** beside the VS Code fork — not feature parity, not Monaco, not plugins.

## In scope (this MVP)

| Capability | Bar |
|---|---|
| Open workspace | Open a real folder path (fixture + typed path). OS dialog when Runtime hook exists. |
| File tree | Bounded scan; skip `node_modules` / `.git` / vendor. |
| Edit file | Native `<textarea>` bound to document buffer (dirty tracking). |
| Save file | Write active document back to disk (Cmd/Ctrl+S / command palette). |
| New file | Create relative path in workspace from explorer. |
| Delete file | Delete selected file from explorer (files only). |
| Rename file | Rename selected file via New-path field. |
| Find in file | Match list + next/prev in active document. |
| Replace in file | Replace once / replace all using find + replace fields. |
| Quick Open | Cmd+P filter workspace files by name/path. |
| Prefs | Persist theme, last path, panel visibility, recent paths under `.velocity/prefs.txt`. |
| Recent projects | Launch screen lists prefs recent paths (falls back to mock list). |
| Document stats | Status bar shows line + byte counts for active document. |
| Copy path | Command / button copies active tab path into toast. |
| Go to line | Cmd+G jump label for active document line count. |
| Close tab | Soft confirm when dirty; second close discards. |
| Search | Bounded in-process text search over scanned files (no ripgrep). |
| SCM | `git status --porcelain` + branch via governor (lazy on SCM panel). |
| Command palette | Open Folder, Save, Search, Git refresh, Terminal, theme, safe mode. |
| Terminal | Pipe-based shell via Process Governor; runtime uses async `fx.spawn` (tests sync). |
| Agent panel | Local task board only — no network AI. |
| Telemetry | Off. |

## Explicitly out of MVP

- Monaco / rich editor island
- Real PTY / interactive shell
- LSP / Debug / Search index / ripgrep process
- Plugin downloads / marketplace
- OS folder dialog (stretch; path entry ships first)
- Electron workbench changes

## Success criteria

1. `native check` / `test` / `build` pass
2. Open fixture → edit → save → re-open shows change
3. Run a shell command in terminal panel; output captured; governor tracks it
4. Search finds known fixture symbols; SCM panel refreshes without crashing
5. First paint stays free of plugins/LSP/git/terminal spawn
