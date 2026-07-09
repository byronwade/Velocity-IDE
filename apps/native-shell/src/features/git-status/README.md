# Git Status

- **id:** `feature.git-status`
- **mode:** `dev`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `1`
- **activation:** `onViewVisible:scm`, `onWorkspaceOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
