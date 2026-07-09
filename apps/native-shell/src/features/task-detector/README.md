# Task Detector

- **id:** `feature.task-detector`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`, `onTaskRun`, `onCommand:task-detector.refresh`

Discovers up to 32 root npm scripts, `.vscode/tasks.json` shell/process tasks,
and simple Makefile targets on workspace open and manual refresh. Precedence is
npm → tasks.json → Makefile with first-name-wins deduplication. Names, commands,
and source labels live in bounded owned buffers.

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
