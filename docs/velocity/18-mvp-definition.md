# Velocity MVP Definition

Ship a **usable daily-driver core** beside the VS Code fork — not feature parity, not Monaco, not plugins.

## In scope (this MVP)

| Capability | Bar |
|---|---|
| Open workspace | Open a real folder path (fixture + typed path). OS dialog when Runtime hook exists. |
| File tree | Bounded scan; skip `node_modules` / `.git` / vendor. |
| Edit file | Native `<textarea>` bound to document buffer (dirty tracking). |
| Save file | Write active document back to disk (Cmd/Ctrl+S / command palette). |
| Save all | Clear dirty markers / save active dirty buffer across tabs. |
| New file | Create relative path in workspace from explorer. |
| Delete file | Soft-confirm then delete selected file from explorer (files only). |
| Rename file | Rename selected file via New-path field. |
| Explorer filter | Filter tree by name/path substring. |
| Reveal in explorer | Select active editor file in the tree. |
| Find in file | Match list + next/prev in active document. |
| Replace in file | Replace once / replace all using find + replace fields. |
| Quick Open | Cmd+P filter workspace files by name/path. |
| Prefs | Persist theme, last path, panel visibility, recent paths under `.velocity/prefs.txt`. |
| Recent projects | Launch screen lists prefs recent paths (falls back to mock list). |
| Document stats | Status bar shows line + byte counts for active document. |
| Breadcrumb | Editor header shows active relative path. |
| Copy path | Command / button copies active tab path into toast. |
| Auto Save | Optional; persists in prefs; writes on each edit when on. |
| Find case | Toggle case-sensitive find (persisted). |
| Go to line | Cmd+G jump label for active document line count. |
| Close tab | Soft confirm when dirty; second close discards. |
| Search | Bounded in-process text search over scanned files (no ripgrep). |
| SCM | `git status --porcelain` + branch via governor; click entry to open file. |
| Reopen last | Launch / command palette reopens prefs `last_path`. |
| Clear find | Clears find/replace fields and match list. |
| Escape dismiss | Closes palette → quick open → clears find (priority order). |
| Duplicate line | Appends a copy of the last document line (MVP). |
| Toggle comment | Cmd+/ toggles `//` / `#` / HTML comments on all lines. |
| Indent / Outdent | Indent or outdent whole document by 2 spaces. |
| Reopen closed tab | Cmd+Shift+T restores last closed file tab. |
| Problems panel | Scans TODO/FIXME/HACK/XXX markers; click to open. |
| SCM diff preview | Selecting a git entry loads bounded `git diff` text. |
| Workspace counts | Explorer + status bar show file/node counts. |
| Dirty tab marker | Active tab title shows ` *` while unsaved. |
| Search hit count | Search status badge reports `N hits`. |
| Terminal history | ↑/↓ recall last commands (in-session). |
| Close Other / Close All | Tab bar + palette close non-active or all tabs (pin blocks close). |
| Pin active tab | Pin/unpin active tab; pinned tab refuses close until unpinned. |
| Save hygiene | Prefs: trim trailing whitespace + insert final newline on save. |
| Text transforms | Upper / lower / sort lines / reverse lines on active document. |
| Focus mode | Hides left panel, agent, and terminal chrome for editing. |
| Shortcuts help | Overlay lists core keybindings (Cmd+Shift+/). |
| Delete / join / move lines | Last-line MVP ops (no caret API yet); Cmd+Shift+K deletes. |
| Undo last edit | Single-level undo for transforms, replace, and textarea edits (Cmd+Z). |
| Revert file | Reload active file from disk; undo restores discarded buffer. |
| Copy absolute path | Join workspace root + relative path into toast. |
| EOL in status | Document stats show LF / CRLF. |
| Next / Previous tab | Ctrl+Tab / Ctrl+Shift+Tab cycle open tabs. |
| Remove / insert blank lines | Strip blank lines or append a blank line at end. |
| Copy file name | Basename of active path into toast. |
| Word count | Status bar includes words; command shows toast. |
| Indent size | Prefs cycle 2/4 spaces; indent/outdent use it. |
| Tabs ↔ spaces | Convert leading indent using current indent size. |
| Sort unique | Sort lines and drop exact duplicates. |
| Encoding label | Status shows ASCII vs UTF-8 (byte heuristic). |
| CRLF ↔ LF | Convert document line endings. |
| Find whole word | Prefs toggle; match only at word boundaries. |
| Duplicate file | Explorer Dup creates `name_copy.ext` beside selection. |
| Search case | Workspace search case-sensitive toggle (persisted). |
| Insert timestamp | Appends UTC `YYYY-MM-DD HH:MM:SS` to the document. |
| Toggle sidebar | Independent left explorer chrome (`Cmd+B`). |
| Title case | Transform words to Title Case. |
| Collapse blank lines | Reduce consecutive blank lines to one. |
| Copy all tab paths | Join open tab paths into toast (newline-separated). |
| New untitled | `Cmd+N` creates `Untitled-N.txt` in the workspace. |
| SCM stage / commit | Stage all (`git add -A`) + commit with message field. |
| SCM unstage / discard | Unstage all (`git reset HEAD`); discard working tree with soft confirm. |
| Refresh explorer | Rescan workspace tree while preserving open tabs. |
| Close saved tabs | Close non-active clean tabs (keeps dirty + pinned + active). |
| Compare with saved | Toast whether the buffer matches disk (byte/line summary). |
| Copy git branch | Copy current branch name into toast. |
| Clear recent projects | Soft-confirm clear of prefs recent list. |
| Insert UUID | Append a deterministic UUID-shaped id to the document. |
| Format document | Trim trailing whitespace + ensure final newline (`Shift+Alt+F` / Fmt). Preserves CRLF. |
| Hard wrap | Wrap long lines at column 80. |
| Copy document | Copy active buffer into toast (truncated if huge). |
| Go to symbol | Jump toast to first line matching find query (case-insensitive). |
| New folder | Create relative directory from New-path field. |
| File size | Toast active buffer byte size. |
| Word wrap pref | Toggle + persist soft wrap preference (label; textarea wrap later). |
| Close tab shortcut | `Cmd+W` closes the active tab. |
| Notifications | Toast bar above status, auto-dismiss (sticky for soft-confirms), bounded history panel. |
| Update check | Settings “Check for Updates” shows in-app banner/toast (dev stub; quiet boot — no banner on launch). |
| Window chrome | Trailing inset spacer; Minimize/Close via Effects; fullscreen toast when chrome insets clear. |
| Settings page | Cursor-like grouped sections (Appearance / Editor / Workspace / Features / About) with search. |
| File tree polish | Indent + folder/file marks; selecting a folder does not open an editor. |
| Editor-first layout | Search / SCM / Problems live in the left sidebar; editor stays centered (Cursor-like). |
| Quiet chrome | Tab transforms + find/replace hidden by default; Cmd+F opens find; agent/terminal closed by default. |
| Trim blank lines | Strip leading/trailing blank lines from the document. |
| Command palette | Filtered by query; Open Folder, Save, Search, Git, Terminal, theme, safe mode. |
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
