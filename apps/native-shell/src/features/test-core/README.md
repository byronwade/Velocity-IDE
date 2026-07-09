# Test Core

- **id:** `feature.test-core`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onTestRun`

Runs the exact `test` task or deterministic first `test:*` fallback. Run,
rerun, pass/fail/cancel state, Stop, diagnostics, and output all share the
existing one-process governed terminal lifecycle. Per-test discovery remains
out of scope.
