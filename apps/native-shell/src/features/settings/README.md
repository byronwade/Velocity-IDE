# Settings

- **id:** `feature.settings`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onFirstPaintDone`, `onCommand:settings.toggle`

Settings search exposes the actual preferences persisted by `core/prefs.zig`,
including workspace-search case/whole-word choices and a bounded disk polling
interval cycle (500, 1000, 2000, or 5000 ms). `core/settings_store.zig` is a
metadata index whose keys are compile-time checked against `Prefs`.
