# Quick Open

- **id:** `feature.quick-open`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onFirstPaintDone`, `onCommand:quick-open.toggle`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

Results are bounded to 48 files and sorted deterministically by exact basename,
basename prefix, path-segment prefix, ordered fuzzy match, then substring.
Recent files break equal-score ties; path ordering is the stable final tie-break.
