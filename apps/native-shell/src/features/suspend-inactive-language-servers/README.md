# Suspend Inactive Language Servers

- **id:** `feature.suspend-inactive-language-servers`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `2`
- **maxProcesses:** `0`
- **activation:** `onCommand:suspend-inactive-language-servers.open`, `onFirstPaintDone`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
