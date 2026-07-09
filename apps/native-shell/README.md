# Velocity Native Shell

Codename **Velocity** (rename-ready). Native SDK app shell for the new IDE.

## Requirements

- Node.js 20+
- `@native-sdk/cli` (`npm install -g @native-sdk/cli` or local install)
- Zig toolchain (CLI can download the pinned version)

## Commands

```bash
# from apps/native-shell
npm run check    # validate markup + app.zon
npm run test     # headless UI tests
npm run dev      # open native window (macOS primary; Linux/Windows supported by SDK)
npm run build    # ReleaseFast binary
npm run perf-smoke
npm run task-smoke
```

Or with the CLI directly:

```bash
native check
native test
native dev
native build
```

Use `native check --strict` after model or markup changes. The test suite also
refreshes the model contract and checks command/shortcut registry integrity.

External file changes are checked with bounded polling during editing and safe
save operations. Use **Refresh Files from Disk** from the command palette for an
immediate full check. A recurring timer is intentionally not wired until the
Native SDK effects lifecycle exposes a verified app-lifetime polling contract;
the persisted `disk_poll_interval_ms` preference is ready for that timer.

Closing through the shell's **Close Window** command writes the bounded session
to `<workspace>/.velocity/hot-exit.bin`; reopening that workspace restores open
tabs and dirty working copies.

Root `package.json` scripts are detected on workspace open and manual refresh.
Select one in the Terminal bottom panel or press **Cmd+Shift+B** to run the
current selection through the terminal and Process Governor. Task output is
parsed into Problems when the process exits.

Workspace replacement lives in Search: enter search and replacement text,
preview affected files, then confirm Apply twice. It refuses matching open tabs
with unsaved or externally changed contents. Source Control provides per-file
Stage, Unstage, and guarded Restore controls in addition to Stage All and
Commit.

Workspace Search incrementally runs after a 220 ms debounce and supports case,
whole-word, include, and exclude controls. Path patterns are comma-separated:
`*` matches any characters, while patterns without `*` match a path prefix or
suffix. Search and workspace replace use the same scope and match options.
Editor Back/Forward keeps 32 workspace-relative path + line locations for
explicit navigation jumps; Quick Open uses deterministic fuzzy/path ranking.

Undo and redo histories are independently bounded per open tab and survive tab
switches. Confirmed conflict overwrites create stable backups under
`.velocity/backups/`; use **Restore Active File from Backup** to preview and
double-confirm a restore. Restore refuses dirty buffers or missing backups.
Explorer deletion supports files and empty directories only. Directory deletion
is double-confirmed and recursive tree deletion is always refused.

# Layout

| Path | Role |
|---|---|
| `src/app.native` | Declarative IDE shell UI |
| `src/main.zig` | Window / tokens / shortcuts wiring |
| `src/model/app_model.zig` | TEA model + mock data |
| `src/core/` | Feature registry, activation, commands, settings |
| `src/features/` | One module per VS Code/Velocity feature category |
| `src/processes/` | Process Governor |
| `src/theme/tokens.zig` | Design tokens |
| `src/perf/` | Perf snapshot + budgets |
| `src/plugins/` | Manifest + permissions stubs |
| `src/bridge/` | Typed editor backend/state/event scaffold; textarea runtime only |
| `src/lsp/` | Bounded JSON-RPC/session/diagnostic scaffold; no process transport |
| `src/terminal/` | Pipe runner plus bounded PTY protocol; PTY transport unavailable |

`src/core/command_registry.zig` is the source of truth for palette metadata,
availability, optional feature ownership, and dispatch coverage declarations.
`model/app_model.zig` consumes its dependency-neutral palette projection.
`src/core/keybinding_registry.zig` owns the Native SDK-compatible shortcut
records, canonical command aliases, supported-key constraints, and generated
shortcut-help items; `main.zig` only projects those records into SDK types.
Registry guards reject duplicate IDs/chords, orphan bindings, unsupported keys,
stale shortcut hints, and unknown declared feature IDs. Mock performance,
update, and plugin surfaces are labeled **Limited**; the no-op New Agent Task
command is hidden until it has an operational implementation.

## Feature modules

200 stubs under `src/features/` with `feature.json`, README, model, messages, perf budget.
See `docs/velocity/14-feature-parity-matrix.md`.


## Product docs

See `/docs/velocity/`.

The editor, LSP, and PTY protocol boundaries are scaffolds, not operational
rich integrations. Exact Native SDK unblock criteria are tracked in
`docs/velocity/native-sdk-blockers.md`. In particular, textarea gutters and an
app-lifetime recurring Effects timer still lack stable SDK contracts.

## Legal / design

Cursor and Vercel are inspiration only. No copied logos, assets, CSS, or trade dress.
