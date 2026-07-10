# Velocity IDE

Velocity is an experimental, standalone native IDE built with Zig and Native
SDK. The shell is usable for focused workspace editing and is not yet a
production daily driver.

## Status and features

- 252 native unit/model/UI tests and eight end-to-end smoke suites
- Bounded workspace explorer, search, tabs, editing, safe saves, and recovery
- Governed terminal, task, test, and command-profile execution (pipe based, not
  a PTY or debugger)
- Problems, basic Git status/actions, read-only bounded diff review, and
  literal-only snippets
- Explorer collapse/filter controls and measured-or-unavailable performance HUD
- No LSP, rich editor island, plugin marketplace, or network AI yet

## Architecture

The product lives in `apps/native-shell`: `.native` markup renders the shell,
while Zig models own workspace state, process governance, and bounded feature
logic. Small future-facing interfaces live under `packages/`. See
[the architecture guide](docs/velocity/01-architecture.md).

## Quick start

Node.js 22 and Linux GTK 4/WebKitGTK 6 development packages are required.

```bash
npm install
npm run check
npm test
npm run build
npm run dev
```

`npm install` reproducibly installs Native SDK CLI 0.4.0 from `.tools`' tracked
lockfile. Run `npm run doctor`, `npm run smoke`, or an individual
`npm run smoke:<name>` for diagnostics and end-to-end coverage.

## Screenshots

Screenshots are not checked in yet; the current UI and feature boundaries are
documented in the [native shell guide](apps/native-shell/README.md) and
[MVP definition](docs/velocity/18-mvp-definition.md).

## Documentation

- [Documentation index](docs/README.md)
- [Current product status](VELOCITY.md)
- [Running the app](docs/velocity/10-running-the-app.md)
- [Feature parity research](docs/velocity/11-vscode-feature-parity-research.md)

Microsoft VS Code is an external behavioral and architecture research reference:
https://github.com/microsoft/vscode. Its source is not part of this working tree.
