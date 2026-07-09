# Legacy VSIX Bridge

- **id:** `feature.legacy-vsix-bridge`
- **mode:** `legacy`
- **status:** `stub`
- **implementation:** `legacy`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `64`
- **maxProcesses:** `1`
- **activation:** `never`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
