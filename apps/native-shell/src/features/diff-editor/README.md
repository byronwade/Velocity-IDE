# Diff Editor

- **id:** `feature.diff-editor`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`

## Rules

- Read-only overlay; opening a review never replaces the active working copy.
- Renders bounded unified line metadata, context, additions, and deletions.
- Reviews at most 256 lines from each in-memory side, 320 rendered lines, and 512 bytes per rendered line. Truncation is explicit.
- Copy writes only to the application internal buffer and does not claim OS clipboard access.
