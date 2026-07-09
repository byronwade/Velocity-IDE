# Local History

- **id:** `feature.local-history`
- **mode:** `heavy`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `32`
- **maxProcesses:** `0`
- **activation:** `onCommand:local-history.open`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
