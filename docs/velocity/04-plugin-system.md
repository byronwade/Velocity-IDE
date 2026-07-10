# Plugin System

## Philosophy

Native, permissioned plugins are default. VS Code extensions are **legacy compatibility**, not the goal.

## Current status

No plugin runtime, manifest parser, package installer, or marketplace client is
implemented. `apps/native-shell/src/plugins/permissions.zig` contains the
tested bounded permission model. Planned plugin feature IDs and budgets live in
`apps/native-shell/src/core/feature_catalog.json`.

The eventual manifest is expected to cover identity, engine/runtime,
activation, contributions, permissions, signatures, repository/license, and
performance budgets. That is design intent, not a current file format.

## Permissions (default deny)

filesystem.read/write, network, terminal, shell, credentials, clipboard, environment, workspace.scan, webview, nativeBinary, aiTools.

## Activation

No plugin activation before first paint. On-demand / idle / file-type after paint only.

## Legacy VSIX bridge

Documented for later: sandboxed host, not implemented or enabled.
