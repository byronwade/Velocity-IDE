# Plugin Host Process

- **id:** `feature.plugin-host-process`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `32`
- **maxProcesses:** `1`
- **activation:** `onPluginInstall`, `onCommand:plugin-host-process.open`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
