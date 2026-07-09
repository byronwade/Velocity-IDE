# Performance Budget

Exact targets for Velocity. Targets are budgets, not measured claims.

| Metric | Target |
|---|---|
| Native window visible | < 300 ms |
| Usable shell | < 500 ms |
| Editor placeholder ready | < 700 ms |
| Monaco ready (bridge milestone) | < 1500 ms |
| Terminal placeholder open | < 50 ms |
| Native terminal open | < 200 ms |
| Command palette open | < 50 ms |
| Idle memory before editor WebView | Dramatically below Electron baseline |
| Plugin activation before first paint | **0** |
| Network before first paint | **0** |

## Instrumentation

- `apps/native-shell/src/perf/startup_timer.zig` uses the Native SDK monotonic
  clock and presented-frame callback.
- **Boot to first observed nonblank paint** starts at in-process `main` entry
  and ends at the first nonblank frame observed by `on_frame`. The SDK does not
  call that hook for its installing frame, which is stated in the HUD.
- **SDK first frame latency** is the SDK's surface-creation-to-first-frame
  value. **First chrome callback** is geometry delivery, not proof of window
  visibility.
- Palette and terminal-panel latency run from the open request to a subsequent
  presented frame while that UI is visible.
- External process launch timing is intentionally separate and requires an
  out-of-process harness.
- Process and ownership totals come from the Process Governor. Feature totals
  come from the registry. RSS and unsupported process metrics display `n/a`.
- UI command: **Refresh Performance Metrics**.
- `scripts/perf-smoke.sh` builds and boots the app, exercises both measured UI
  paths, refreshes the HUD, and rejects placeholder claims.

Do not publish fake benchmarks.
