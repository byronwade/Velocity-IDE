# 99 · Open questions (answer before betting)

Carried from the research pass — these blocked confident prioritization and
deserve their own investigation before large investments:

1. **Independent performance truth.** No reproducible third-party benchmark
   exists for startup/latency/memory across Zed, Cursor, VS Code on identical
   hardware. Before publishing Velocity's budgets as claims, build the
   harness (see 02-performance P2) and measure all four.

2. **Debugger table stakes.** The "Zed's debugger launched without
   watch/stack-trace" claim was REFUTED (it shipped call stacks at launch).
   Actual 2026 debugger baselines across the three need a focused pass before
   scoping Velocity's DAP milestone: which of watch expressions, conditional
   breakpoints, data breakpoints, inline values are genuinely expected at
   launch?

3. **Extension surface sufficiency.** Is themes+grammars+MCP+ACP enough to
   avoid ecosystem lock-out, and what can Zed's WASM extension API actually
   do today? Study before designing Velocity's WASM ABI.

4. **Parallel-agent merge semantics.** When multiple worktree-isolated agents
   touch overlapping files, what are the review/merge semantics? Cursor's
   answer is unclear from public docs; Velocity should design this
   deliberately (per-file approve/revert exists in the review flow item).

5. **Refuted claims — do not reuse.** (a) "GPUI draws all primitives via SDF
   fragment shaders with no tessellation" — overreach; glyphs are CPU-
   rasterized into a GPU atlas. (b) The Zed debugger launch-gap claim above.

6. **Marketing numbers are vendor positioning.** Cursor's "4x faster
   Composer" rests on a closed benchmark (methodology publicly questioned);
   Zed's <1s/<10ms/3-4x page is self-reported. Cite only as positioning.
