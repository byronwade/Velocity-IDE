# Workspace Search

- **id:** `feature.workspace-search`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `1`
- **activation:** `onSearch`, `onCommand:workspace-search.run`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
