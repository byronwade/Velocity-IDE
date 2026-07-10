# Copilot instructions for Velocity IDE

- Treat this repository as standalone Velocity IDE source. VS Code is only an
  external reference at https://github.com/microsoft/vscode.
- Work primarily in `apps/native-shell` (Zig plus `.native` markup); do not
  recreate removed Code-OSS directories, package scaffolding, or per-feature
  stub directories.
- Use root npm scripts and the pinned CLI in `.tools`; never add a second
  `@native-sdk/cli` dependency.
- Keep file scans, text buffers, histories, output, and process counts bounded.
- Spawn terminal, task, test, SCM, and profile work through the Process
  Governor.
- Do not claim performance without measurements; use explicit unavailable
  states when the host cannot provide a metric.
- Preserve literal-only snippet safety and the bounded, read-only nature of diff
  review unless a deliberate design change includes tests and docs.
- Feature metadata is authored in `src/core/feature_catalog.json`.
  `src/core/feature_registry.zig` is generated with
  `npm run features:generate`; use `npm run features:check` to detect drift.
- Run `npm run check`, `npm test`, and relevant smoke suites before completing
  code changes.
