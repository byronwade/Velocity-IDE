# Task Runner

- **id:** `feature.task-runner`
- **mode:** `dev`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `2`
- **activation:** `onTaskRun`, `onCommand:task-runner.run`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
