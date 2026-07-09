# Task Runner

- **id:** `feature.task-runner`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `1`
- **activation:** `onTaskRun`, `onCommand:task-runner.run`, `Cmd+Shift+B`

Runs the selected detected npm, tasks.json, or Make task through the integrated
terminal and Process Governor. One terminal/task process is allowed; Stop owns
the same cancellation path. Output is bounded and mirrored into the labeled
Output channel, and diagnostics are parsed into clickable Problems on exit.

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
