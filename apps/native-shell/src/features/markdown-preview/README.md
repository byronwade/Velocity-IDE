# Markdown Preview

- **id:** `feature.markdown-preview`
- **mode:** `dev`
- **status:** `stub`
- **implementation:** `webview`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `0`
- **activation:** `onCommand:markdown-preview.open`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
