# Performance Budget

Exact targets for Velocity. Measure before claiming; scaffold HUD uses **mock** values only.

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

## Scaffold

- `apps/native-shell/src/perf/perf_model.zig` — snapshot fields
- UI command: **Run Performance Check** (mock populate)
- `scripts/perf-smoke.sh` — prints placeholder metrics

Do not publish fake benchmarks.
