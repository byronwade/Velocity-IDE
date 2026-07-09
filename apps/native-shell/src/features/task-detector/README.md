# Task Detector

- **id:** `feature.task-detector`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`, `onTaskRun`, `onCommand:task-detector.refresh`

Discovers up to 32 root `package.json` scripts on workspace open and manual
refresh. Names and commands are parsed into bounded owned buffers; malformed,
oversized, or missing manifests are reported without affecting the workspace.

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
