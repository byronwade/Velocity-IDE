# Native SDK Migration

## Why Native SDK is promising

- Native window + GPU canvas without Electron
- Declarative `.native` markup + Zig TEA (`Model` / `Msg` / `update`)
- Hot reload for UI; compile-time markup checks in release
- Explicit permissions and small default surface

## What cannot be ported from VS Code

- Workbench contribution model and extension host lifecycle
- Electron BrowserWindow / Chromium shell assumptions
- xterm addon ecosystem as the default terminal
- Marketplace activation and extension activation events

## Why we are not porting the workbench

Porting would re-import the coupling we are escaping. Velocity needs a new shell with budgets and removable features.

## Why build beside the fork

Keep Code-OSS as reference, compatibility bunker, and fallback while Velocity matures.

## Risks

| Risk | Notes |
|---|---|
| Pre-1.0 SDK | APIs and Linux host deps still moving |
| Platform gaps | macOS primary; Linux needs GTK/WebKit link today even for canvas shell |
| Toolchain | Zig pinned via CLI download |
| Editor quality | Monaco island later; native editor TBD |

## Go / no-go checklist

- [x] `native check` passes
- [x] `native test` passes
- [x] `native build` produces a binary (Linux deps installed)
- [ ] Interactive polish on macOS primary target
- [ ] Real perf marks under budget
- [ ] Workspace file I/O without Electron

## Fallback

If Native SDK is not ready for a milestone: keep shipping research on the VS Code fork path, and keep Velocity docs/scaffold advancing offline until the SDK host is viable on target platforms.
