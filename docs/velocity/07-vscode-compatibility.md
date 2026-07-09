# VS Code Compatibility

## Policy

VS Code / VSIX compatibility is **optional legacy mode**, not the default product path.

## Scaffold

- Legacy bridge is **disabled**
- Documented only in `04-plugin-system.md` and architecture notes
- Do not activate the VS Code extension host from Velocity startup

## Later

A sandboxed VSIX host may run selected extensions with explicit permissions and no first-paint coupling.
