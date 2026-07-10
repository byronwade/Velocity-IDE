# Git Diff

- **id:** `feature.git-diff`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `1`
- **activation:** `onViewVisible:scm`, `onWorkspaceOpen`

## Rules

- `Open SCM Diff` opens the shared read-only Diff Review instead of replacing the editor or showing raw text in the sidebar.
- Git XY status selects safely available staged (`git diff --cached`) and unstaged (`git diff`) modes; untracked files use bounded `--no-index`.
- Paths are passed as literal argv values after `--`; no shell interpolation is used.
- Raw Git output is capped at 32 KiB before bounded line projection.
