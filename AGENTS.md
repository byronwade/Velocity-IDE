# Velocity IDE agent guide

## Scope

This is a standalone Velocity IDE repository. Product code is under
`apps/native-shell`; shared future-facing contracts are under `packages`.
Microsoft VS Code is an external research reference only. Do not recreate
removed upstream paths or copy upstream source into this tree.

## Tooling

- Use Node.js 22.
- Run `npm install` at the root; it installs the pinned Native SDK CLI through
  `.tools/package-lock.json`.
- Use root scripts: `npm run check`, `npm test`, `npm run build`,
  `npm run dev`, `npm run doctor`, and `npm run smoke:<name>`.
- Do not add another `@native-sdk/cli` dependency.

## Code expectations

- Keep Zig and UI state bounded; avoid unbounded scans, buffers, and process
  creation.
- Route spawned work through the Process Governor.
- Keep startup claims measurable and report unavailable metrics honestly.
- Add or update tests for behavior changes and run the narrowest relevant smoke
  suite.
- Preserve portable scripts: derive paths from the repository and retain the
  caller's `PATH`.
- Update docs when commands, architecture, or supported behavior changes.
