# Architecture

## Repo layout

```
apps/native-shell/     # Native SDK product shell
docs/velocity/
tools/                 # Deterministic repository generators
.tools/                # Locked Native SDK CLI installer metadata
```

Within the shell, `src/model/app_model.zig` owns the TEA application model,
`src/workspace/` owns bounded workspace behavior, and `src/processes/` owns
governed command execution. `src/core/feature_catalog.json` is the canonical
200-entry feature metadata source; `src/core/feature_registry.zig` is generated.

## Systems

1. **Native Shell** — windows, layout, palette, panels, status bar
2. **Editor Surface** — native textarea today; rich editor island is blocked
3. **Workspace Core** — documents, settings, keybindings, search
4. **Agent Surface** — composer, task cards, permissions summary
5. **Terminal** — governed pipe runner today; PTY transport unavailable
6. **LSP Broker** — bounded protocol only; no language server transport
7. **Plugin Runtime** — planned permissioned native plugins
8. **Registry Client** — planned signed curated plugins
9. **Legacy VSIX Bridge** — documented only; disabled

## Dependency boundaries

- Shell has no dependency on VS Code workbench modules. External reference:
  https://github.com/microsoft/vscode.
- Plugins cannot reach shell/network/fs without permissions.
- Any future LSP process must be owned by the broker and Process Governor.
- Any future editor WebView must remain isolated to the editor surface.

## Current boundary

The MVP implements bounded workspace editing, recovery, search, basic Git
operations, and governed pipe-based commands. Agent, plugin registry, rich
editor, PTY, debugger, and LSP transport surfaces are not operational.
