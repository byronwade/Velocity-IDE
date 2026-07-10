# File Explorer

- **id:** `feature.file-explorer`
- **mode:** `core`
- **status:** `working`
- **startupAllowed:** `false` — tree loads on workspace open only
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`

## Behavior

- Renders bounded file tree from `workspace/scanner.zig` (max 256 nodes, depth 8).
- A bounded path-keyed collapse store projects visible rows from the complete
  scan. Folder chevrons, Collapse All, Expand All, refresh, and CRUD preserve
  selection/collapse where the path still exists.
- Filtering ignores collapse while active and includes every ancestor of a
  matching path. Clearing the filter restores collapse; Reveal expands only
  the active file's ancestors.
- Explorer rows reuse the single bounded SCM porcelain snapshot for Modified,
  Staged, Untracked, and Conflict decorations. No Git command runs per row,
  and decorations clear when SCM reports a non-Git workspace.
- The header reports `scan capped` when the 256-node bound truncates a scan.
- Skips `node_modules`, `.git`, `vendor`, build caches by default.
- Selecting a file reads up to 16KB text into the editor island placeholder.
- File deletion and empty-directory deletion require confirmation twice.
  Non-empty directories are never removed recursively.
- No file watchers yet.

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- See `docs/velocity/14-feature-parity-matrix.md`.
