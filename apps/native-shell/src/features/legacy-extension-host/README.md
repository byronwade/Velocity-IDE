# Legacy Extension Host

- **id:** `feature.legacy-extension-host`
- **mode:** `legacy`
- **status:** `stub`
- **implementation:** `legacy`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `128`
- **maxProcesses:** `1`
- **activation:** `never`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
