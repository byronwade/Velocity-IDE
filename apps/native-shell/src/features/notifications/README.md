# Notifications

- **id:** `feature.notifications`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `4`
- **maxProcesses:** `0`
- **activation:** `onFirstPaintDone`, `onCommand:notifications.toggle`

Toast UX remains transient while every new toast is projected into a bounded
structured store. Entries carry severity, source, dedupe count, and only
allowlisted action IDs (`open_problems` or `reload_workspace`). The accessible
notification center filters by severity and source without allocating.
