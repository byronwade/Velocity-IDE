# Breadcrumbs

- **id:** `feature.breadcrumbs`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `2`
- **maxProcesses:** `0`
- **activation:** `onFirstPaintDone`, `onCommand:breadcrumbs.toggle`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

The editor chrome exposes file breadcrumbs and bounded Back/Forward navigation.
Navigation stores up to 32 workspace-relative path + line locations, ignores
same-position transitions, and truncates the forward branch after a new jump.
Problems, search, definition, breadcrumbs, quick open, line, symbol, and outline
jumps participate. History is workspace-session state and is not persisted.
