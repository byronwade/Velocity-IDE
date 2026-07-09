# Backups

- **id:** `feature.backups`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onWorkspaceOpen`

## Rules

- Confirmed conflict overwrites first copy the disk version to
  `.velocity/backups/<relative-path>.bak`.
- Original and replacement content are both bounded to the editor file limit.
- Backup failure leaves the original file unchanged.
