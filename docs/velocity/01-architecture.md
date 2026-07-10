# Architecture

## Repo layout

```
apps/native-shell/     # Native SDK product shell
packages/ide-core/     # Shared workspace/command concepts (TS stubs)
packages/plugin-sdk/   # Manifest + permission schemas
packages/registry-client/
docs/velocity/
.tools/                # Locked Native SDK CLI installer metadata
```

## Systems

1. **Native Shell** — windows, layout, palette, panels, status bar
2. **Editor Island** — placeholder → Monaco WebView → evaluate native editor
3. **Workspace Core** — documents, settings, keybindings, search
4. **Agent Surface** — composer, task cards, permissions summary
5. **Terminal** — mock → native PTY
6. **LSP Broker** — external language servers
7. **Plugin Runtime** — permissioned native plugins
8. **Registry Client** — signed curated plugins
9. **Legacy VSIX Bridge** — documented only; disabled

## Dependency boundaries

- Shell has no dependency on VS Code workbench modules. External reference:
  https://github.com/microsoft/vscode.
- Plugins cannot reach shell/network/fs without permissions.
- LSP broker is the only language-intelligence process manager.
- Editor island is the only allowed WebView in the product shell.

## Milestone 1 mocks

- Recent projects, file tree, tabs, agent tasks, terminal lines, registry rows, perf HUD
