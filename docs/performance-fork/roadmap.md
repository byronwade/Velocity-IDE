# Performance Fork Roadmap

## Completed (this pass)

1. Architecture audit + product profile docs
2. Feature flag infrastructure (`performanceForkFeatures.ts`)
3. Workbench entrypoint split (`core` / `developer` / `compat`)
4. Core Mode defaults: telemetry/welcome/chat/MCP/notebook/testing/sync gated off
5. Empty marketplace `builtInExtensions` for Core
6. Lean terminal entry + addon feature gates
7. Extension activation budget API (design + helpers)
8. Focus Core default settings
9. Static `npm run perf-fork` harness
10. Build-system options doc (keep Gulp/esbuild short term)

## Next

1. Wire `evaluateExtensionActivationBudget` into extension activation path
2. Runtime cold-start / memory capture in perf harness (requires compile + Electron)
3. Built-in local extension packaging filter by mode
4. Shell profile / env resolution caching for terminal
5. Status bar / activity contribution allowlist
6. Compat-mode CI smoke job
7. Only after metrics: extension Webpack → Rspack experiment

## Rollback

Always available via `--perf-fork-mode=compat` or `performanceFork.mode` in product/settings.
