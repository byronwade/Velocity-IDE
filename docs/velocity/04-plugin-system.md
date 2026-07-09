# Plugin System

## Philosophy

Native, permissioned plugins are default. VS Code extensions are **legacy compatibility**, not the goal.

## Manifest (draft)

See `packages/plugin-sdk/src/manifest.schema.json` and `apps/native-shell/src/plugins/manifest.zig`.

Fields: id, name, publisher, version, engine, runtime, activation, contributes, permissions, signature, repository, license, performanceBudget.

## Permissions (default deny)

filesystem.read/write, network, terminal, shell, credentials, clipboard, environment, workspace.scan, webview, nativeBinary, aiTools.

## Activation

No plugin activation before first paint. On-demand / idle / file-type after paint only.

## Legacy VSIX bridge

Documented for later: sandboxed host, not enabled in scaffold.
