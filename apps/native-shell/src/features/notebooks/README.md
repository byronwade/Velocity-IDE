# Notebooks

- **id:** `feature.notebooks`
- **mode:** `heavy`
- **status:** `stub`
- **implementation:** `webview`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `64`
- **maxProcesses:** `0`
- **activation:** `onCommand:notebooks.open`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
