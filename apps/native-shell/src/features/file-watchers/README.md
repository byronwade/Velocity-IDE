# File Watchers

- **id:** `feature.file-watchers`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `1`
- **activation:** `onWorkspaceOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
