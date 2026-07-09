# Workspace Search

- **id:** `feature.workspace-search`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `0`
- **activation:** `onSearch`, `onCommand:workspace-search.run`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

The current implementation scans bounded text files already discovered by the
workspace scanner and returns at most 64 matching lines. Search supports case
and whole-word parity with workspace replace plus comma-separated include and
exclude patterns. `*` matches any characters; a pattern without `*` matches an
exact path prefix or suffix. Patterns and query text are bounded in the model.

Typing schedules one 220 ms one-shot Effects timer under a fixed key. New input
replaces that timer, empty input cancels it, and Search/Enter runs immediately.
Timer rejection is surfaced and leaves manual search available.
