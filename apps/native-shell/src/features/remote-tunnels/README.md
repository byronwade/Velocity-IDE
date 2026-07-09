# Remote Tunnels

- **id:** `feature.remote-tunnels`
- **mode:** `remote`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `0`
- **activation:** `never`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
