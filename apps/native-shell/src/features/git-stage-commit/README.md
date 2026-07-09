# Git Stage/Commit

- **id:** `feature.git-stage-commit`
- **mode:** `dev`
- **status:** `working`
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

Supports repository-root status refresh, per-file and all-file stage/unstage,
and commit with an argv-safe message. Tracked-file restore is separately
double-confirmed and refuses dirty open tabs and untracked files.
