# Velocity Gap Register

Generated 2026-07-10. Cross-references: `feature_catalog.json` (authoritative:
17 working / 4 prototype / 179 stub), `docs/velocity/14-feature-parity-matrix.md`,
`18-mvp-definition.md`, `native-sdk-blockers.md`, and market research in
`docs/research/`.

## A. Catalog status inaccuracies (fix before next `features:generate`)

The matrix (docs/14) and MVP definition (docs/18) claim shipped behavior that
`feature_catalog.json` still marks `stub`. Since the catalog is authoritative
and generates `feature_registry.zig`, this drift misreports Velocity to every
downstream consumer.

| Catalog ID | Catalog says | Matrix / MVP says | Suggested catalog status |
|---|---|---|---|
| `feature.dirty-state` | stub | matrix: **working** (bounded per-tab copies, undo/redo, Save All) | working |
| `feature.search-results` | stub | matrix: **working** (clickable path/line results + nav history) | working |
| `feature.hot-exit` | stub | matrix: **working**; MVP ships `.velocity/hot-exit.bin` restore | working |
| `feature.backups` | stub | matrix: **working** (backup before confirmed overwrite, guarded restore) | working |
| `feature.problem-matchers` | stub | matrix: **working** (TS/Zig/GCC + Vitest/Jest) | working |
| `feature.test-core` | stub | matrix: **working** (run/rerun, state machine, governed process) | working |
| `feature.test-output` | stub | matrix: **working** (Output mirror + assertion Problems) | working |
| `feature.test-discovery` | stub | matrix: **partial** (task-name discovery only) | partial (add status value if needed) |
| `feature.auto-save` | stub | MVP ships Auto Save (prefs-persisted, write-on-edit) | working (bounded) |
| `feature.command-palette` | stub | docs/17: "working for implemented commands"; MVP ships filtered palette | partial |
| `feature.find-replace` | stub | MVP ships find + replace once/all, case/whole-word, clear-find | partial (no caret-anchored find yet) |
| `feature.outline` / `feature.symbols` | stub | MVP ships heuristic outline + Go to Symbol palette | partial (heuristic, not LSP) |
| `feature.go-to-definition` | stub | MVP ships bounded text-search definition jump | partial (heuristic, not LSP) |
| `feature.recent-projects` | stub | MVP: launch screen lists prefs recent paths | working |
| `feature.status-bar`, `feature.sidebar`, `feature.panel`, `feature.tabs` | stub | MVP ships status bar stats, toggleable sidebar, bottom panel tabs, pin/cycle/close tabs | partial |
| `feature.themes` | stub | docs/17: theme tokens **done**; prefs persist theme | partial |
| `feature.formatting` | stub | MVP ships Format Document (trim + final newline, Shift+Alt+F) | partial (not a real formatter) |
| `feature.performance-hud` | stub | docs/17: "measured-or-unavailable UI + model" exists | partial |

Note the reverse direction is clean: nothing marked `working` in the catalog
appears overstated — matrix notes honestly bound each one (read-only overlays,
truncation caps, literal argv). The `prototype` entries correctly carry
`blockedBySdk`. Recommendation: add a formal `partial` status to the catalog
schema (matrix already uses it for test-discovery) instead of rounding to
stub/working.

## B. Market-value gaps (high external value, low Velocity status)

Ordered by severity = (market value × frequency) vs current status.

| Gap | Market evidence | Velocity status | Path |
|---|---|---|---|
| **Syntax highlighting** | Baseline in all three competitors; absence disqualifies daily-driver use | stub, blocked on editor decoration API | SDK ask #1; interim read-only highlighted peek/diff spike |
| **Language intelligence (LSP)** | Stickiest VS Code capability; Zed's zero-config LSP is a switch driver | broker scaffold, transport SDK-blocked | SDK ask #2; build registries now (queue #13) |
| **Interactive terminal** | Named in every "daily essentials" list; continuous use | pipe runner only, PTY SDK-blocked | SDK ask #3 |
| **Fast whole-repo search** | Large-repo pain is the top VS Code complaint class; Zed/ripgrep speed assumed | bounded in-process scan (256 nodes, 16KB reads) | ripgrep adapter is READY — queue #1 |
| **Git branch operations** | Zed invested heavily in git UX 2026; branch switch is daily | status/branches stub (diff/stage/commit working) | argv git — queue #3 |
| **Keybinding customization + VS Code import** | Muscle memory is switch-cost #1; Cursor won by zero switch cost | stub | queue #11; import is cheap adoption leverage |
| **Workspace trust gate** | VS Code doubling down 2026; prerequisite of agent era | stub | queue #10, native-only work |
| **Debugger** | Zed 1.0 shipping DAP "erased the last objection" narrative | all stubs, transport-blocked | keep P1-blocked; do not attempt pre-SDK |
| **Extension/plugin ecosystem** | The one moat Zed still can't cross | all stubs; host process transport-blocked | trust substrate design spike (queue #17) |
| **Accessibility** | Org procurement requirement; VS Code ships a11y signals | stub; SDK a11y forwarding undocumented | spike (queue #22) |
| **Remote dev** | VS Code's moat; "biggest reason teams adopt" | stub P3 | correctly deferred; depends on transports anyway |

## C. Counter-positioning opportunities (market anti-value Velocity already targets)

| Competitor pain | Evidence | Velocity asset (status) |
|---|---|---|
| AI bloat you can't disable | Jan 2026 HN wave to Zed (250+ comments) | `no-agents-mode`, `no-extensions-mode`, `feature-toggle-matrix` — all stub but cheap and native; ship early, market loudly |
| Unbounded memory (tsserver 35GB; Cursor +0.5–1GB embeddings) | GH issues ts-go#2780, vscode#140090; r/cursor | bounded budgets + Process Governor (working for current procs); `ram-budget-dashboard`, `memory-pressure-mode` stubs |
| Opaque agent billing/permissions | Cursor pricing backlash, migration to Claude Code | `agent-permissions`, `agent-terminal-approval`, autonomy slider — design as substrate pre-AI |
| Privacy fragility (Cursor/SpaceX backlash) | 2026 acquisition concerns | telemetry off, local-first adapters — already MVP posture; document it |

## D. Process gaps

1. **No `partial` status in catalog schema** while matrix uses it → drift is
   structural, not accidental.
2. **`docs/velocity/14` and `18` disagree with the catalog** (§A). Whichever is
   wrong, `npm run features:check` does not catch semantic drift, only
   generation drift — consider a doc-lint that diffs matrix status column
   against the catalog.
3. **Perf claims discipline is good** (measured-or-n/a) — keep it; it is a
   credibility differentiator vs benchmark-marketing competitors.
