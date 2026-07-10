# Native SDK Migration

## Why Native SDK is promising

- Native window + GPU canvas without Electron
- Declarative `.native` markup + Zig TEA (`Model` / `Msg` / `update`)
- Hot reload for UI; compile-time markup checks in release
- Explicit permissions and small default surface

## Behaviors that are not source-porting targets

- Workbench contribution model and extension host lifecycle
- Electron BrowserWindow / Chromium shell assumptions
- xterm addon ecosystem as the default terminal
- Marketplace activation and extension activation events

## Why we are not porting the workbench

Porting would re-import the coupling we are escaping. Velocity needs a new shell with budgets and removable features.

## External comparison baseline

Use published Microsoft VS Code builds and
https://github.com/microsoft/vscode for behavioral research and repeatable
comparison scenarios. No local upstream source tree is required.

## Risks

| Risk | Notes |
|---|---|
| Pre-1.0 SDK | APIs and Linux host deps still moving |
| Platform gaps | Linux is CI-validated and still links GTK/WebKit even for the canvas shell; other platforms are unvalidated |
| Toolchain | Zig pinned via CLI download |
| Editor quality | Monaco island later; native editor TBD |

## Go / no-go checklist

- [x] Root `npm run check` passes (feature drift, tests, strict app validation)
- [x] Root `npm test` passes
- [x] Root `npm run build` produces a binary on Linux
- [ ] Validate build, tests, and interaction on macOS and Windows
- [x] Honest measured-or-unavailable performance instrumentation
- [x] Workspace file I/O without Electron
- [ ] Repeatable release performance measurements under budget

## Fallback

If Native SDK blocks a milestone, narrow or pause that milestone while keeping
Velocity's standalone contracts and documentation viable. Compare externally
with the Microsoft VS Code baseline where useful; do not restore an upstream
source tree as a fallback.
