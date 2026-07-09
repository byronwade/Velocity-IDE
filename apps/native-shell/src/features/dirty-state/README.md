# Dirty State

- **id:** `feature.dirty-state`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `2`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`

## Rules

- Bounded working-copy storage keeps up to 8 open tabs (16 KiB each).
- Dirty text survives tab switches, explorer rescans, and Save All.
- Dirty tabs require explicit confirmation before close/bulk close.
- Safe Save fingerprints disk content and blocks silent external overwrites.
