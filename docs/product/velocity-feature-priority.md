# Velocity Feature Priority Queue

Generated 2026-07-10 from market research (`docs/research/*-feature-value.md`)
mapped onto `feature_catalog.json`, `docs/velocity/14/17/18`, and
`native-sdk-blockers.md`.

## Scoring model

`score = 0.30·DailyFreq + 0.25·Unblock + 0.20·Feasibility + 0.15·MarketEvidence + 0.10·PerfAlignment` (each 1–5).

- **Feasibility** respects hard constraints: textarea has no gutter/decoration/
  caret API (rich editor surface SDK-blocked); LSP/DAP/plugin-host need a
  long-lived streamed child process (SDK-blocked); interactive PTY SDK-blocked.
  Single-shot argv spawn via Process Governor **is proven** (git, tasks, pipe
  terminal).
- **Classifications**: WORKING (ships today), PARTIAL (core shipped, gaps
  remain), READY (implementable now in current architecture), SPIKE (needs a
  bounded investigation first), BLOCKED (needs SDK capability), DEFERRED
  (deliberately later — includes all AI-Later).

## Ranked implementation queue

| # | Item (catalog IDs) | DF | UP | FE | ME | PA | Score | Class | Bucket | Rationale / next step |
|---|---|--|--|--|--|--|------|-------|--------|---|
| 1 | Ripgrep-backed search (`ripgrep-adapter`, `quick-search`, upgrade `workspace-search`/`search-results`) | 5 | 4 | 4 | 5 | 5 | **4.55** | READY | Core | Single-shot governed spawn is proven; replaces bounded in-process scan; unlocks large-repo story (top VS Code complaint) and feeds symbol/def heuristics. Bundle or detect rg binary; bound output. |
| 2 | Command surface completion (`command-palette`, `command-search`) | 5 | 4 | 5 | 4 | 3 | **4.40** | PARTIAL | Core | Palette works for implemented commands (catalog says stub — drift). Finish: full command registry, fuzzy command search, recently-used ordering. Every later feature ships through this surface. |
| 3 | Git core completion (`scm-core`, `git-provider`, `git-status`, `git-branches`) | 5 | 4 | 5 | 4 | 3 | **4.15**\* | READY | Dev | diff + stage/commit already working via argv git. Add branch list/switch/create, refresh-on-focus, status decorations in explorer. Zed's git panel shows daily-driver value; argv-only (no shell) keeps security posture. (\*UP=4: unblocks decorations, merge UX, history.) |
| 4 | Interactive terminal PTY (`terminal`) | 5 | 5 | 1 | 5 | 4 | **4.10** | BLOCKED | Core | SDK ask #2 (per blockers log: PTY spawn, streams, resize, proc-tree lifecycle). Pipe runner remains the stopgap. Highest daily-frequency blocked item; keep protocol scaffold warm. |
| 5 | Workbench chrome formalization (`tabs`, `editor-groups`, `layout`, `status-bar`, `sidebar`, `panel`, `activity-rail`) | 5 | 3 | 5 | 3 | 3 | **4.00** | PARTIAL | Core | MVP already ships tabs/pin/cycle, sidebar, bottom panel, status bar — catalog marks all stub (drift). Remaining: split editor groups, layout persistence, drag-reorder tabs. |
| 6 | Rich editor island (`editor-island`, `monaco-bridge`; unblocks `syntax-highlighting`, `multi-cursor`, `folding`, `bracket-matching`, gutter) | 5 | 5 | 1 | 5 | 2 | **3.90** | BLOCKED | Core | SDK ask #1: WebView lifecycle + messaging + focus/IME/a11y, or textarea gutter/decoration + caret/scroll contract. This is the ceiling on "daily driver" adoption — syntax highlighting alone is disqualifying when absent. |
| 7 | LSP transport + JS/TS pack (`lsp-broker` runtime, `lsp-process-manager`, `js-ts-language-pack`) | 5 | 5 | 1 | 5 | 2 | **3.90** | BLOCKED | Dev | SDK ask #3: long-lived streamed child process w/ backpressure + cancellation + governor ownership. Stickiest capability in all three competitors. Broker protocol scaffold already bounded. |
| 8 | Agent trust substrate (`agent-review`, `agent-apply`, `agent-permissions`, `agent-terminal-approval`, `agent-autonomy-slider`) | 3 | 4 | 4 | 5 | 3 | **3.75** | DEFERRED (AI-Later) | AI-Later | Highest-scoring AI item because the substrate is native UI (diff review already working) and shared with Git/refactor flows. Build only the reusable diff-review + approval-gate primitives pre-AI; no network AI until agent phase. |
| 9 | File watchers (`file-watchers`) | 4 | 4 | 3 | 3 | 4 | **3.65** | SPIKE | Core | Keyed polling timer works today. Spike: does SDK expose native FS events? If not, tiered polling (active file fast, tree slow) within bounds. Unblocks fresh explorer/git/search without rescan cost. |
| 10 | Workspace Trust Plus (`workspace-trust-plus`, `workspace-process-sandbox` design) | 3 | 4 | 4 | 4 | 3 | **3.60** | READY | Core | Trust gate before tasks/git hooks/terminal run in a folder; VS Code 2026 doubled down (browse-then-trust). Prereq for plugins and agents; native UI + prefs only. |
| 11 | Keybindings customization (`keybindings`) | 4 | 3 | 4 | 4 | 2 | **3.55** | READY | Core | Muscle-memory is switch-cost #1; ship VS Code-style JSON + conflict view; import VS Code keymap = adoption lever (Cursor's zero-switch-cost lesson). |
| 12 | Syntax highlighting (`syntax-highlighting`, `semantic-tokens`) | 5 | 3 | 1 | 5 | 3 | **3.50** | BLOCKED | Core | Subsumed by #6; listed separately because it is the single most continuous-value missing feature. Possible pre-SDK spike: read-only highlighted render for peek/diff views. |
| 13 | LSP readiness pack (`language-registry`, `language-server-registry`, `diagnostic-registry`, `completion-registry`, `language-client` shell) | 2 | 5 | 4 | 4 | 2 | **3.45** | SPIKE | Dev | Native registries + governor budget wiring so LSP lands in days, not months, when transport unblocks. Bounded, no processes. |
| 14 | Problems + matchers (`problems`, `problem-matchers`, `diagnostics` panel side) | 4 | 2 | 5 | 3 | 3 | **3.45** | WORKING | Dev | Matrix/MVP show TS/Zig/GCC/Vitest/Jest matchers + Problems panel shipped; catalog says stub — fix drift. Remaining: more matchers, marker API for future LSP. |
| 15 | Perf instrumentation surface (`performance-hud`, `ram-budget-dashboard`, `process-governor-ui`, `startup-flamegraph`) | 3 | 2 | 5 | 3 | 5 | **3.35** | PARTIAL | Core | HUD exists as measured-or-unavailable model. This is the marketing feature: Zed proves perf sells, and no competitor shows user-facing resource governance. Needs SDK RSS/proc counters for full value. |
| 16 | Themes (`themes`) | 3 | 2 | 5 | 3 | 3 | **3.15** | READY | Core | Token system done; ship theme picker + a few bundled themes + VS Code theme JSON import (adoption lever). |
| 17 | Plugin trust substrate (`plugin-manifest`, `plugin-permissions`, `plugin-signatures`, `plugin-scorecard`) | 2 | 4 | 3 | 4 | 3 | **3.10** | SPIKE | Dev | Native metadata/permission model is READY-able; `plugin-host-process`/`native-plugin-runtime` share the LSP streamed-transport blocker. Design now, host later. |
| 18 | Terminal ergonomics (`terminal-tabs`, `terminal-find`, `terminal-links`) | 4 | 2 | 3 | 3 | 3 | **3.05** | DEFERRED | Core | Low value on a pipe runner; re-rank to READY when PTY unblocks. |
| 19 | Inline suggestions / Tab-style completion (`inline-suggestions`) | 5 | 2 | 1 | 5 | 1 | **3.05** | DEFERRED (AI-Later) | AI-Later | #1 Cursor value, but needs ghost-text decoration (blocked on #6) + network AI (later phase). |
| 20 | Debugger (`debug-core`, `debug-adapter-protocol`, `breakpoints`, …) | 3 | 4 | 1 | 4 | 2 | **2.90** | BLOCKED | Dev | Same streamed-transport blocker as LSP; breakpoint gutter also blocked on #6. Zed's history: adoption ceiling, not adoption floor — correct at P1-blocked. |
| 21 | Multi-cursor / column select (`multi-cursor`, `column-selection`) | 4 | 2 | 1 | 4 | 2 | **2.70** | BLOCKED | Core | Needs caret/selection API (part of #6). |
| 22 | Accessibility core (`accessibility-core`) | 3 | 3 | 2 | 3 | 2 | **2.70** | SPIKE | Core | Org-adoption requirement. Spike what the SDK forwards (focus order, screen-reader tree); blockers log flags a11y forwarding as undocumented. |
| 23 | Auto save / hot exit / backups (`auto-save`, `hot-exit`, `backups`) | 3 | 1 | 5 | 2 | 2 | **2.65** | WORKING | Core | All three shipped per MVP/matrix; catalog says stub — fix drift. |
| 24 | Remote dev (`remote-ssh`, `remote-containers`, `port-forwarding`) | 3 | 3 | 1 | 4 | 2 | **2.65** | DEFERRED | Remote | VS Code's moat and Zed's last-closed gap, but architecturally premature; revisit after LSP/PTY transports exist (they are prerequisites anyway). |
| 25 | Git merge conflicts UI (`git-merge-conflicts`) | 2 | 2 | 3 | 3 | 2 | **2.35** | READY | Dev | Bounded conflict-block parser + pick-ours/theirs actions works in textarea; full 3-way merge editor waits on #6. |
| 26 | Everything else P3/heavy (`minimap`, `notebooks`, `settings-sync`, `profiles`, `search-editor`, `coverage`, `pull-request-provider`, collaboration) | ≤3 | ≤2 | var | ≤3 | ≤2 | <2.3 | DEFERRED | Heavy/Collab | No market evidence these drive switching; several (notebooks, webviews) also SDK-blocked. |

## SDK ask priority (from this ranking)

1. **Editor surface contract** (gutter/decoration + caret/scroll, or WebView
   lifecycle + IME/a11y) — gates #6, #12, #19, #21, and half of #20.
2. **Long-lived streamed child process** (backpressure, cancel, proc-tree,
   governor ownership) — gates #7 LSP, #20 DAP, #17 plugin host.
3. **PTY** — gates #4 and re-rates #18.
4. **FS events + RSS/process counters** — upgrades #9 and #15 from
   polling/partial to full value.

## Execution guidance

- Near-term sprint order (no SDK movement assumed): **1 → 2 → 3 → 10 → 11 → 16
  → 9(spike) → 13(spike) → 15 → 14 cleanup**.
- All catalog-status drift found during this pass is listed in
  `velocity-gap-register.md` — fix the catalog before generating the registry
  again, since the catalog is authoritative.
