# Compare Files

- **id:** `feature.compare-files`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`

## Rules

- `Compare with Saved` compares the active in-memory text against a bounded disk read.
- Results open in the shared read-only Diff Review overlay; the working copy remains active and unchanged.
- Matching files still render a valid metadata/context review, and large reviews report truncation.
