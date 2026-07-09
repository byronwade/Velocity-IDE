# Terminal Memory Inspector

- **id:** `feature.terminal-memory-inspector`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `4`
- **maxProcesses:** `0`
- **activation:** `onCommand:terminal-memory-inspector.open`, `onFirstPaintDone`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
