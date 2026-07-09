# Hot Exit

- **id:** `feature.hot-exit`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `4`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`

## Rules

- Close Window writes a bounded session to `.velocity/hot-exit.bin`.
- Reopening the matching workspace restores up to 8 tabs and dirty text.
- Missing files and malformed sessions are skipped without replacing live state.
