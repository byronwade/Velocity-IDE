# Search Editor

- **id:** `feature.search-editor`
- **mode:** `heavy`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `32`
- **maxProcesses:** `0`
- **activation:** `onSearch`, `onCommand:search-editor.run`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
