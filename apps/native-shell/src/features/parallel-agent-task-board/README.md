# Parallel Agent Task Board

- **id:** `feature.parallel-agent-task-board`
- **mode:** `agent`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onCommand:parallel-agent-task-board.open`, `onFirstPaintDone`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
