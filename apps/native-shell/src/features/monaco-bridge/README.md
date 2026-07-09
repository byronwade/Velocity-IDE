# Monaco Bridge

- **id:** `feature.monaco-bridge`
- **mode:** `core`
- **status:** `prototype` — typed editor boundary only; runtime blocked by SDK
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

No WebView is created. Runtime support requires a stable SDK WebView lifecycle,
bidirectional messaging, and documented focus, keyboard, IME, and
accessibility forwarding.
