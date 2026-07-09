# Search Replace

- **id:** `feature.search-replace`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onSearch`, `onCommand:search-replace.run`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

The Search sidebar previews bounded literal replacements across scanned text
files, then requires a second confirmation to apply. Apply refuses matching
open tabs that are dirty or stale on disk and safely rescans/reloads clean tabs
after writing. Preview and apply share workspace search's case sensitivity,
whole-word boundary checks, and include/exclude path scope.
