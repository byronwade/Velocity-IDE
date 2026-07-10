# Zed: What Developers Actually Value (2026)

Researched 2026-07-10. Sources: zed.dev releases/compare pages, zed 0.23x
release notes (git panel, project diff multibuffer, agent compaction), the Jan
2026 "I switched from VSCode to Zed" HN thread (250+ comments), 2026 comparison
benchmarks (2ms vs 12ms typing latency; ~2x startup; large memory gap).

Zed matters most to Velocity: it is the proof that **performance is a product**,
and the closest competitor to Velocity's positioning.

## Why developers switch to Zed

1. **Latency as a feature** — ~2ms input latency (vs ~12ms VS Code), sub-second
   cold start, GPU-native rendering. Users describe it as "the speed VS Code
   used to have." This is Velocity's exact thesis.
2. **Low memory** — repeatedly benchmarked at a fraction of VS Code/Cursor RSS.
3. **Calm, opt-in AI** — the anti-bloat editor. AI exists (agent panel, edit
   predictions) but is ignorable/disable-able. The HN switch wave was driven by
   VS Code's un-removable AI chrome.
4. **First-class Git UX** — 2026 git panel: project diff as an *editable
   multibuffer* (fix mistakes inside the diff before staging), staged/unstaged
   views, git graph, blame. Reviewers call it best-in-class.
5. **Multibuffer** — edit excerpts from many files in one surface (diffs,
   search results, diagnostics all become editable buffers). Zed's signature UX
   invention.
6. **Built-in LSP, tree-sitter, no extension needed** — zero-config language
   intelligence for mainstream languages.
7. **Collaboration** — shared buffers/channels, humans + agents in one buffer.
   Valued by a small segment; not a switch driver for most.

## What kept people OFF Zed (now mostly fixed — cautionary timeline)

Until 2025: no debugger, weak remote, no Windows, thin extensions. Zed 1.0
(April 2026) shipped DAP debugging, SSH/WSL/dev-container remote, Jupyter REPL —
and reviews immediately shifted to "most practical objections erased; ecosystem
breadth is the remaining gap." Lesson: an MVP editor is adoptable *without*
these, but debugger + remote define the ceiling of who can switch.

## Feature value table

| Feature | User problem | Freq | Why valued | Velocity status | SDK requirement | Mem/proc | Security | Priority | Bucket |
|---|---|---|---|---|---|---|---|---|---|
| Input latency / startup speed | Editor feels heavy | continuous | THE switch driver; 2ms vs 12ms is perceptible | native shell exists; perf HUD partial (`performance-hud` stub — flag) | measured perf counters (partially n/a) | negative (it's the budget) | none | P0 — the brand | Core |
| Low memory footprint | Laptop RAM pressure | continuous | Benchmark headline vs Electron | bounded budgets in catalog; `ram-budget-dashboard` stub | RSS measurement API | n/a | none | P0 — the brand | Core |
| Opt-in, killable AI | AI fatigue | continuous | Drove the 2026 HN switch wave | `no-agents-mode`/`no-extensions-mode`/`feature-toggle-matrix` stub | none | none | none | P0 — cheap, differentiating | Core |
| Git panel + project-diff multibuffer | Review/stage without CLI | daily | Best-in-class 2026 git UX; editable diffs | git diff/stage/commit **working** (read-only, bounded); branches/history stub | none for argv git; editable-diff needs rich editor | 16MB + 1 proc | argv-only | P0 | Dev |
| Built-in LSP (zero config) | Setup friction | continuous | "It just works" without extension hunt | SDK-blocked transport | streamed child process | 1 proc per server, budgeted | trust gate | P0 (blocked) | Dev |
| Tree-sitter syntax highlighting | Fast, accurate coloring | continuous | Baseline expectation | stub; blocked on decoration API | editor decoration surface | 16MB | low | P0 (blocked) | Core |
| Multibuffer (search/diagnostics as editable buffers) | Bulk fix across files | daily | Signature UX; makes search-replace and diagnostics fixing fast | search-replace **working** (preview + confirm, not editable-in-place) | rich editor surface | medium | low | P2 aspiration | Dev |
| Native debugger (DAP) | Was the #1 "can't switch" gap pre-1.0 | weekly | Its arrival re-rated Zed for teams | stub | streamed child process (same as LSP) | 1 proc | adapter executes code | P1 (blocked) | Dev |
| Remote dev (SSH/WSL/containers) | Was gap #2 | daily for segment | Closed "the single largest gap vs VS Code" | stub P3 | remote transport | remote procs | credentials | P3 | Remote |
| Collaboration (shared buffers, humans+agents) | Pairing/mob | occasional | Loved by a niche; not a switch driver | none planned near-term | network + CRDT | medium | session auth | P3 | Collaboration |
| Extensions (thin but growing) | Niche tooling | occasional | The remaining reason people stay on VS Code | plugin system stub | plugin host process | budgeted | signatures/permissions | P1 | Dev |

## Velocity-vs-Zed positioning notes

- Zed already occupies "fast native editor." Velocity's defensible deltas:
  **bounded-everything guarantees** (visible budgets, Process Governor,
  kill-all, memory-pressure mode — Zed has no user-facing resource governance),
  **trust/permission-first plugins**, and eventually governed agents.
- Zed's timeline shows the adoption ceiling order: editor feel → language
  intelligence → git → terminal → debugger → remote. Velocity's implementation
  sequence should mirror it and not skip ahead.
