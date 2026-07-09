# Build System Options

> Investigate before replacing anything. First make the product smaller; then optimize bundling.

## Current pipeline (Code-OSS)

| Stage | Tool | Notes |
|---|---|---|
| Dev transpile | Gulp + TypeScript / esbuild transpile tasks | `npm run watch`, `compile` |
| Layer checks | `tsgo`, custom checkers | `valid-layers-check` |
| Production bundle | **esbuild** (`build/lib/optimize.ts`) | `bundle-vscode`, `minify-vscode` |
| Built-in extensions | **Webpack** | `extensions/**/extension.webpack.config.js` |
| Electron package | `@vscode/gulp-electron` + gulpfile.vscode | Platform builds |
| Dev web helper | Vite (`build/vite`) | Not the desktop production path |

**Important:** Core workbench production bundling is already esbuild, not Webpack. Webpack remains for extensions.

## “Versailles / Vercel native SDK”

No in-repo reference to a “Versailles” native SDK. Closest relevant ecosystems:

| Candidate | Relevance |
|---|---|
| Vercel Turbopack | Dev bundler for Next; not an Electron workbench drop-in |
| Rolldown | Rust bundler (Rollup-compatible); early for Electron+workers |
| Rspack | Webpack-compatible; useful if migrating extension Webpack configs |
| esbuild | **Already used** for VS Code core minify/bundle |
| tsgo / native TypeScript | Already in scripts for typecheck speed |

Recommendation: do **not** chase a speculative Vercel-native Electron SDK. Optimize on top of existing esbuild + trim inputs.

## Option comparison

### Keep Gulp + esbuild (short term) — **Recommended**

| Question | Answer |
|---|---|
| Electron renderer? | Yes (current) |
| VS Code module expectations? | Yes |
| CSS/assets/workers? | Yes via existing pipeline |
| Extension host? | Separate entry in `buildfile.ts` |
| Reduce startup bundle? | Indirectly — smaller entry graph helps more |
| Improve build times? | Incremental already |
| Runtime startup? | Dominated by what is imported, not minify tool |
| Risk | Low |
| Migration | N/A |
| Rollback | N/A |

### esbuild further (more entry splitting)

Split `workbench.desktop.main` into async feature chunks (already started with dynamic `import()` for packs). Risk: medium. Improves runtime startup.

### Rspack for extensions only

| Question | Answer |
|---|---|
| Electron renderer? | Not needed |
| Preserve webpack configs? | High compatibility |
| Extension host code? | Extensions yes |
| Build times? | Likely faster extension builds |
| Runtime startup? | Little (extensions load later) |
| Risk | Medium |
| Path | Swap webpack in `build/lib/extensions.ts` |
| Rollback | Keep webpack configs |

### Rolldown / Vite-Rolldown

| Question | Answer |
|---|---|
| Electron renderer? | Experimental |
| Module expectations? | Unknown for VS Code’s ESM + AMD addon loader |
| CSS/workers? | Partial |
| Risk | High |
| Runtime vs build | Mostly build time |
| Recommendation | Revisit after Core Mode metrics |

### Full Webpack removal from extensions via esbuild

Feasible long-term; many extension configs are simple. Risk medium-high due to native/node externals.

## Decision

1. **Now:** keep Gulp/esbuild; shrink `workbench.*.main` import graph (this PR).
2. **Next:** measure bundle size with `scripts/perf-fork/bundle-size.mjs`.
3. **Later:** optional Rspack experiment for extension builds only.
4. **Avoid:** rewriting the Electron renderer bundler before Core Mode boots and benchmarks stabilize.

## Rollback plan

Any bundler experiment stays on a branch; `minify-vscode` / `bundle-vscode` remain the production path on `main` until metrics prove a win.
