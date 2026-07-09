# Activity Rail

- **id:** `feature.activity-rail`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `True`
- **memoryBudgetMB:** `2`
- **maxProcesses:** `0`
- **activation:** `onStartupCritical`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
