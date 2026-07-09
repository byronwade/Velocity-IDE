# CSS/HTML Language Pack

- **id:** `feature.css-html-language-pack`
- **mode:** `dev`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `1`
- **activation:** `onLanguage`, `onFileOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
