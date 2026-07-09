# Memory Strategy

## Principles
- First paint before plugins/LSP/terminal/git/debug.
- Bounded buffers (terminal, output, diagnostics, search).
- Virtualize large trees/lists.
- No unbounded caches; every cache has max size + eviction.
- No scanning `node_modules` / `.git` / vendor by default.
- Memory Pressure Mode disables heavy features and freezes background terminals / idle LSPs.

## Budgets
See `06-performance-budget.md` and per-feature `perf_budget.md`.

## Instrumentation
Performance HUD + RAM Budget Dashboard (mock until samplers wired).
