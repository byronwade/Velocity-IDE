# Performance Fork — Product Profile

## Vision

A performance-first IDE forged from Code-OSS: Monaco + extension API compatibility, dramatically less default surface area, sub-second perceived startup, low idle memory, command-driven UI.

This is **not** “VS Code with a theme.” Default product mode is **Core**.

## Runtime modes

### Mode 1 — Core Mode (default)

Absolute minimum IDE:

- Monaco editor, tabs/editor groups
- File explorer
- Settings JSON + keybindings
- Command palette + quick open
- Basic search (files + text)
- Terminal (lean addons)
- Theme support
- Extension host available; activation budgeted / deferred
- No telemetry, surveys, welcome, chat, notebook, testing UI
- No remote tunnels, account sync, MCP, profile import/export UI, walkthroughs
- No process explorer unless developer tools enabled

**Activate:** default via `product.json` `performanceFork.mode: "core"`, or `--perf-fork-mode=core`.

### Mode 2 — Developer Mode

Core plus optional packs:

- Git/SCM
- Debug
- Tasks
- Problems/markers (already light in core) + Output
- Extension marketplace UX
- Language server support (via extensions)
- Webviews when extensions demand them
- Testing only when `workbench.testing` enabled
- Timeline / local history / update / emmet / markdown preview / auth / comments

**Activate:** `--perf-fork-mode=developer` or `VSCODE_PERF_FORK_MODE=developer`.

### Mode 3 — Full Compatibility Mode

Near-stock workbench contribution surface for migration and extension compatibility testing. Not the default product.

Includes chat/notebook/welcome/surveys/sync/MCP/telemetry contribs when their flags are on (compat defaults enable most stock packs).

**Activate:** `--perf-fork-mode=compat`.

## Feature flag system

Module: `src/vs/platform/performanceFork/common/performanceForkFeatures.ts`

Resolution order (later wins):

1. Mode build-time defaults
2. `product.json` → `performanceFork.features`
3. Env: `VSCODE_PERF_FORK_MODE`, `VSCODE_PERF_FORK_ENABLE`, `VSCODE_PERF_FORK_DISABLE`
4. CLI: `--perf-fork-mode`, `--perf-fork-enable`, `--perf-fork-disable`
5. User settings: `performanceFork.features` (runtime gates; restart for import-level packs)

## Default settings (Focus Core)

Applied via configuration default overrides when mode ≠ compat:

- `telemetry.telemetryLevel: off`
- `workbench.startupEditor: none`
- Activity bar hidden in Core
- Minimap / sticky scroll / bracket pair guides off
- Extension recommendations ignored
- Shell integration off in Core
- Terminal images/ligatures off
- Calm default theme: Default Light Modern

## Distribution notes

- OSS telemetry remains off (`enableTelemetry: false`).
- Marketplace JS debug built-ins are **not** in Core `builtInExtensions`.
- Copilot `defaultChatAgent` removed from Core product profile.

## Success metrics

| Metric | Target |
|---|---|
| Cold start → first window | Perceived &lt; 1s on modern hardware |
| Idle RSS | Dramatically below stock |
| Modules at first paint | Editor, files, layout, settings, keybindings, explorer, terminal registration, extension scanner, deferred loaders |
| Terminal open | Near-instant |
| Extension activation | Never blocks first paint |
