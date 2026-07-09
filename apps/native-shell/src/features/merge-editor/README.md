# Merge Editor

- **id:** `feature.merge-editor`
- **mode:** `dev`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
