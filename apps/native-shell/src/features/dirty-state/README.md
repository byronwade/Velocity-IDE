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
- Save All continues past conflicts and retains each unsaved/conflicted tab.
- Confirmed overwrites create bounded backups before replacing disk content.
- Disk changes are detected by bounded interaction polling or manual refresh.
- Close Window persists bounded dirty tab state for matching-workspace restore.
