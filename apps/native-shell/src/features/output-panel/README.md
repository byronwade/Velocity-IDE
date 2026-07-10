# Output Panel

- **id:** `feature.output-panel`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onTaskRun`, `onCommand:output-panel.run`

Provides one bounded 48-line registry with All, Task, Test, Launch, Git, and
System projections. Each channel has deterministic counts, filtering, and
clear-selected behavior. Source labels (`npm`, `tasks.json`, `Makefile`,
profile name, `git`, or `velocity`) survive filtering; no projection allocates.
