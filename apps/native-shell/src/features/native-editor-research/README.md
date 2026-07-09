# Native Editor Research

- **id:** `feature.native-editor-research`
- **mode:** `heavy`
- **status:** `stub`
- **implementation:** `deferred`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `0`
- **maxProcesses:** `0`
- **activation:** `onFileOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
