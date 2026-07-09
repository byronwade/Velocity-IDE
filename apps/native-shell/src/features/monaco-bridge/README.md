# Monaco Bridge

- **id:** `feature.monaco-bridge`
- **mode:** `core`
- **status:** `stub`
- **implementation:** `webview`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `80`
- **maxProcesses:** `0`
- **activation:** `onFileOpen`, `onIdle`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
