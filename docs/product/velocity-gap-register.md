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

## Catalog reconciliation (2026-07-10)

Each §A claim was verified against implementing code, tests (`apps/native-shell/src/tests.zig`
or module test blocks), and smoke scripts — not against docs/14 or docs/18 (both carry
their own drift: the matrix still lists command-palette, recent-projects, auto-save,
git-status, and performance-hud as stub). Vocabulary note: the generator
(`tools/generate_feature_registry.py`, `STATUSES = {stub, prototype, working, optimized}`)
does NOT accept `partial`; every §A "partial" suggestion is recorded as `prototype`
(real-but-incomplete). Bar for `working`: end-to-end user-reachable path + tests covering
the important logic + failure states represented + no critical mock.

Post-reconciliation tallies: 27 working / 20 prototype / 153 stub (was 18/4/178).

feature.dirty-state | stub -> working | tests.zig: "dirty tab title gets marker", "save all preserves conflicts while saving unaffected dirty tabs"; workspace/undo_stack.zig (9 tests)
feature.search-results | stub -> working | tests.zig: "open search hit jumps to line toast", "search and line jumps populate back forward navigation and branch", "search status reports hit count"
feature.hot-exit | stub -> working | workspace/hot_exit_store.zig; tests.zig: "close persists hot exit and matching workspace restores dirty session", "hot exit refuses dirty unloaded payload and surfaces persistence failure"
feature.backups | stub -> working | workspace/backup_store.zig (6 tests); tests.zig: "forced overwrite creates backup and refreshes disk baseline", "active backup restore previews confirms and refuses unsafe states"
feature.problem-matchers | stub -> working | workspace/problem_matchers.zig tests: TypeScript, Zig/GCC+ANSI, Vitest/Jest with framework-stack rejection; scripts/diagnostics-smoke.sh
feature.test-core | stub -> working | tests.zig: "workspace tests pass and mirror bounded labeled output", "workspace test cancellation shares the governed Stop lifecycle", "failed workspace test creates one assertion problem and opens Problems"; scripts/test-smoke.sh (pass+fail modes)
feature.test-output | stub -> working | tests.zig: labeled bounded Output mirror + assertion Problems assertions in the three workspace-test tests above
feature.auto-save | stub -> working | app_model.zig:toggleAutoSave/saveActiveDocument-on-edit; tests.zig: "auto save toggle persists preference", "autosave writes backups refreshes fingerprints and preserves external conflicts"
feature.git-status | stub -> working | scm/git_status.zig module tests run real git repos (porcelain/NUL parse, per-path stage/unstage/restore, traversal rejection); tests.zig: "git status refresh on scm activity" (graceful non-repo)
feature.test-discovery | stub -> prototype | task-name discovery only (workspace/task_detector.zig; tests.zig: "fixture task discovery preserves npm precedence and labels every source"); no per-test tree — matrix itself says partial
feature.command-palette | stub -> prototype | tests.zig: "command palette filters by query", "palette projection hides no-op and labels limited commands"; real and tested, but docs/17 scopes it to "working for implemented commands" — §A itself only claims partial
feature.find-replace | stub -> prototype | workspace/find_in_doc.zig, replace.zig; tests.zig: "replace once and all in document", case/whole-word/clear-find tests; no caret-anchored find
feature.outline | stub -> prototype | workspace/outline.zig ("heuristic symbol extraction (no LSP)"); tests.zig: "outline sidebar and symbol palette"
feature.symbols | stub -> prototype | same heuristic source feeds Go to Symbol palette (tests.zig: "outline sidebar and symbol palette", symbol_palette_open)
feature.go-to-definition | stub -> prototype | workspace/go_to_def.zig bounded text search; tests.zig:1490 "go to definition finds symbol in workspace" (assertion is disjunctive/weak — heuristic, not LSP)
feature.recent-projects | stub -> prototype | REJECTED §A's "working": app_model.zig:3169 syncRecentFromPrefs falls back to the static mock `recent_projects` array (fake `~/src/...` paths) whenever prefs are empty — a user-reachable mock on first run fails the no-critical-mock bar. Prefs-backed path is real (tests.zig: "recent projects sync from prefs", "reopen last workspace from prefs")
feature.status-bar | stub -> prototype | doc stats/EOL/file-count tests ("document stats update on edit", "doc stats include eol", "workspace file count label after open"); limited fixed segments
feature.sidebar | stub -> prototype | tests.zig: "sidebar toggle and search case and timestamp", "sidebar keeps editor for search scm problems"; toggle + view switching only
feature.panel | stub -> prototype | tests.zig: "bottom panel tabs terminal output problems", "palette terminal command uses bottom panel state"
feature.tabs | stub -> prototype | tests.zig: "pin blocks close until unpinned", "cycle tabs next and prev", "reopen closed tab restores file", "close all and close other use explicit dirty confirmation flags"; no reorder/preview tabs
feature.themes | stub -> prototype | theme/tokens.zig + prefs.setTheme; tests.zig: "prefs persist theme"; fixed built-in token set only
feature.formatting | stub -> prototype | app_model.zig:formatDocument (trim + final newline + hard wrap; tests.zig: "save hygiene trims trailing whitespace", "format hard wrap copy document go to symbol"); not a real formatter
feature.performance-hud | stub -> prototype | tests.zig: "performance refresh reports measured zeros and unavailable fields honestly" (rss_bytes and external launch latency genuinely unavailable); scripts/perf-smoke.sh
feature.scm-core | stub -> prototype | functional SCM panel end-to-end (tests.zig: "model SCM stages literal path and restore reloads clean open tab", "Git discard refuses an unsaved open tab before confirmation", "open git entry missing is graceful") but git-only; no provider-agnostic SCM core
feature.git-provider | stub -> prototype | real governed argv-git execution lives in scm/git_status.zig and backs the working git-diff/git-stage-commit; no provider process, watching, or refresh daemon

Verified-and-kept (no change):
feature.workspace-search | working (kept) | dual-engine state is honestly covered: tests.zig:464 "ripgrep engine toggle searches or falls back honestly" plus scope/whole-word and incremental one-shot-timer tests — still accurate
feature.git-branches | stub (kept) | only branch-name display + copy_git_branch command exist (app_model.zig:2068, git_status.zig branch buffer); no list/switch/create — display belongs to git-status
feature.ripgrep-adapter | working (kept) | per orchestrator instruction, already updated this cycle

Rejected §A claims:
1. `feature.recent-projects` -> working: rejected (downgraded suggestion to prototype) — static mock fallback on empty prefs, see line above.
2. `partial` as a status value: rejected — generator whitelist has no `partial`; recorded as `prototype` throughout. §A's recommendation to add a formal `partial` status remains open as a schema change (out of scope here).
