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
- The active file can preview and double-confirm restoration from that stable
  path through the editor action or command palette.
- Restore refuses dirty working copies and missing backups, then reloads the
  editor cache and disk fingerprint after a successful write.
- Original and replacement content are both bounded to the editor file limit.
- Backup failure leaves the original file unchanged.
