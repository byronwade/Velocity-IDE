# Webviews

- **id:** `feature.webviews`
- **mode:** `heavy`
- **status:** `stub`
- **implementation:** `webview`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `48`
- **maxProcesses:** `0`
- **activation:** `onCommand:webviews.open`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
