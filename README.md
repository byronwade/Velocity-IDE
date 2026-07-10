# Velocity IDE

Velocity is an experimental standalone IDE built with Zig and Native SDK. Its
focused editing shell is usable, but it is not yet a production daily driver.

For the detailed live capability table and limitations, see
[VELOCITY.md](VELOCITY.md).

## Get started

Use Node.js 22. Linux development additionally requires GTK 4 and WebKitGTK 6.
Linux is currently the only CI-validated platform.

```bash
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev
npm install                   # run at the repository root
npm run check
npm run build
npm run dev
```

`npm install` reproducibly installs Native SDK CLI 0.4.0 from `.tools`' tracked
lockfile. Native commands may download the CLI's official pinned Zig toolchain
when it is missing. `npm run check` verifies generated feature metadata, runs
252 native tests, and performs the strict Native SDK check. `npm test` is
test-only; `npm run smoke` runs all eight Linux UI/process smoke suites.

## Documentation

- [Current product status](VELOCITY.md)
- [Native shell guide](apps/native-shell/README.md)
- [Documentation index](docs/README.md)
- [Running the app](docs/velocity/10-running-the-app.md)
- [Architecture](docs/velocity/01-architecture.md)
- [MVP definition](docs/velocity/18-mvp-definition.md)

Microsoft VS Code is an external behavioral and architecture research reference:
https://github.com/microsoft/vscode. Its source is not part of this working tree.
