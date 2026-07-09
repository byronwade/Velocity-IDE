# Performance HUD

- **id:** `feature.performance-hud`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `4`
- **maxProcesses:** `0`
- **activation:** `onCommand:run_perf`, `onPresentedFrame`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

The HUD records in-process monotonic frame timings and snapshots live Governor
and feature-registry counts. Unsupported fields are shown as `n/a`; it does not
estimate RSS or conflate external launch timing with in-process boot timing.
