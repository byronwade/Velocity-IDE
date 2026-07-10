# 02 · Performance budgets and measurement

Vendor numbers are marketing until reproduced, but the competitive bar they
set is consistent: Zed positions <1 s startup, <10 ms typing latency, and
3-4x lower memory than Electron editors; GPUI's stated frame budget is
8.33 ms (120 FPS). Velocity's honesty-first HUD is the right instrument —
extend it rather than publishing claims.

## Committed budgets (publish only when measured)

| Metric | Budget | Status |
|---|---|---|
| Cold start → first nonblank paint | < 1 s | HUD measures; CI smoke observes ~1.3-4.6 s in software rendering — needs a real-hardware baseline |
| Keystroke → present | < 10 ms | not yet instrumented |
| Frame budget (animation/scroll) | 8.33 ms | not yet instrumented |
| Palette open → present | < 50 ms | measured (~20-26 ms in CI software rendering) |
| Resident memory, empty workspace | < 300 MB | RSS not exposed by SDK yet |

## Todo

- [x] P0 [TS] Humanize HUD values (ms/s, KB/MB) with per-row measured /
      unavailable badges — landed on `claude/ui-redesign-clean-modern-4cxqp4`.
- [ ] P0 [TS] Add keystroke→present latency instrumentation (input event
      timestamp to next presented frame while the editor has focus); surface
      p50/p95 in the HUD, not just last-sample.
- [ ] P0 [TS] Frame-time series in the HUD: worst frame in the last N,
      count over 8.33 ms — adopt GPUI's budget as the internal target.
- [ ] P1 [TS] Real-hardware perf baseline job (not llvmpipe): record startup,
      palette, and typing latency on at least one macOS and one Linux machine
      per release; publish in VELOCITY.md only from these runs.
- [ ] P1 [TS] RSS/memory sampling once the SDK exposes it (perf_model already
      reports it honestly as unavailable); add per-feature memory budgets from
      feature_catalog.json to the HUD.
- [ ] P1 [TS] Startup work audit: nothing but the launch view before first
      paint (activation policy already gates features — verify with a
      measured "work before first frame" counter).
- [ ] P2 [DIFF] Publish a reproducible public benchmark harness (scripted,
      identical hardware, all three competitors) — none of the vendors do
      this credibly; it converts honesty into a marketing asset.
