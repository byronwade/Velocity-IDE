# Python Language Pack

- **id:** `feature.python-language-pack`
- **mode:** `heavy`
- **status:** `stub`
- **implementation:** `process`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `64`
- **maxProcesses:** `1`
- **activation:** `onLanguage`, `onFileOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
