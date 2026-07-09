# Output Panel

- **id:** `feature.output-panel`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onTaskRun`, `onCommand:output-panel.run`

Provides a bounded 48-line channel. Task/test terminal output is mirrored with
channel (`task` or `test`) and source (`npm`, `tasks.json`, or `Makefile`)
labels; system status lines remain separately labeled.
