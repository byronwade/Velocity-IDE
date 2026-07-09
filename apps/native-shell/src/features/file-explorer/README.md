# File Explorer

- **id:** `feature.file-explorer`
- **mode:** `core`
- **status:** `prototype`
- **startupAllowed:** `false` — tree loads on workspace open only
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`

## Behavior (M2)

- Renders bounded file tree from `workspace/scanner.zig` (max 256 nodes, depth 8).
- Skips `node_modules`, `.git`, `vendor`, build caches by default.
- Selecting a file reads up to 16KB text into the editor island placeholder.
- File deletion and empty-directory deletion require confirmation twice.
  Non-empty directories are never removed recursively.
- No file watchers yet.

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- See `docs/velocity/14-feature-parity-matrix.md`.
