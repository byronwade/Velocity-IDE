# Remote SSH

- **id:** `feature.remote-ssh`
- **mode:** `remote`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `32`
- **maxProcesses:** `0`
- **activation:** `onCommand:remote-ssh.open`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
