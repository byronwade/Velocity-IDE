# Fuzzy File Search

- **id:** `feature.fuzzy-file-search`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onSearch`, `onCommand:fuzzy-file-search.run`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

Implemented through Quick Open with bounded deterministic fuzzy/path-segment
ranking and recent-file tie-breaking.
