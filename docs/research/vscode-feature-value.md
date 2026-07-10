# VS Code: What Developers Actually Value (2026)

Researched 2026-07-10. Sources: Stack Overflow Developer Survey 2025 (75.9% usage,
#1 IDE 4th year running — survey.stackoverflow.co/2025), VS Code release notes
v1.109–v1.128 (code.visualstudio.com/updates), microsoft/vscode + TypeScript
GitHub issues, HN/Reddit switch-away threads (news.ycombinator.com/item?id=46498735).

Frequency scale: continuous > hourly > daily > weekly > occasional.
Velocity status = `feature_catalog.json` unless flagged (see gap register).

## Why VS Code wins (value, not features)

1. **It is the default** — ecosystem gravity (extensions, tutorials, team
   conventions, CI, job listings), not any single feature.
2. **Language intelligence that "just works"** — TS/JS IntelliSense, go-to-def,
   rename. This is the single stickiest capability; it is also the #1 complaint
   surface at scale (tsserver OOM to 35GB in monorepos, TS #39263, ts-go #2780).
3. **Integrated terminal + tasks** — kills context switches; hosts any shell.
4. **Remote dev (SSH/WSL/containers)** — repeatedly cited as the moat feature
   ("genuinely ahead of alternatives"); edit remote as if local.
5. **Command palette + keybindings** — everything keyboard-reachable; muscle
   memory is the real lock-in.
6. **Git in the editor** — status/stage/commit/diff daily; GitLens-style blame
   is the most-installed extension category.
7. **Trust model** — Workspace Trust (2026: browse untrusted safely, trust
   later) matters more in the agent era; per-site browser permissions for agents.

## Feature value table

| Feature | User problem solved | Freq | Why valued (evidence) | Velocity status | SDK requirement | Mem/proc | Security | Priority | Bucket |
|---|---|---|---|---|---|---|---|---|---|
| IntelliSense / completions | Don't memorize APIs | continuous | #1 stickiness driver; also #1 perf complaint at scale | `lsp-broker` prototype, transport SDK-blocked | long-lived streamed child proc, backpressure, cancel | 48–64MB/server, 1 proc each | LS runs arbitrary workspace code → trust gate | P0 (blocked) | Dev |
| Go to definition / references | Navigate unfamiliar code | hourly | Top navigation action in every "essential features" list | stub (heuristic text version shipped in MVP — flag) | LSP transport; heuristic works today | low | low | P0 | Dev |
| Integrated terminal | Stay in one window | continuous | Named in every daily-driver list; xterm+PTY | `terminal` prototype, PTY SDK-blocked (pipe runner works) | cross-platform PTY spawn, streams, resize, proc-tree kill | 32MB + shell proc | command execution = highest risk surface | P0 (blocked) | Core |
| Command palette | Discoverability w/o menus | hourly | "Executes virtually every feature"; keyboard-first | stub in catalog; working for implemented commands (flag) | none | 4MB | low | P0 | Core |
| Quick open (Cmd+P) | Reach any file in <1s | continuous | Fastest habitual action; latency-sensitive | **working** | none | 8MB | low | done — keep fast | Core |
| Search across files | Find usage/strings | hourly | ripgrep-backed speed is assumed baseline | `workspace-search` working (bounded, no ripgrep) | single-shot spawn (available) | 24MB + 1 proc | search path escapes need bounding | P0 | Core |
| Git status/stage/commit/diff | Commit without CLI round-trips | daily | Native SCM covers "most daily tasks" | diff + stage/commit **working**; status/provider/branches stub | single-shot argv spawn (proven) | 8–24MB, 1 proc | argv-only, no shell interp (already the pattern) | P0 | Dev |
| Settings + keybindings | Make the editor yours | weekly setup, continuous benefit | Muscle-memory lock-in; keybinding import is a switch-cost killer | settings **working**; keybindings stub | none | 2–8MB | settings.json can enable risky behavior → trust-gate | P0 | Core |
| Tasks + problem matchers | Build/test without leaving | daily | tasks.json ecosystem; errors → clickable Problems | task-runner/detector **working**; matchers working per matrix (catalog says stub — flag) | pipe runner sufficient | 16MB + 1 proc | runs workspace-defined commands → trust gate | P1 | Dev |
| Debugging (DAP) | Inspect running code | weekly (high stakes) | Breakpoint debugging is the #2 "can't leave VS Code" reason after extensions | all debug features stub | same streamed-child transport as LSP | 24MB + adapter proc | adapter executes code | P1 (blocked) | Dev |
| Extensions | Fill every niche | install occasional, benefit continuous | 50k+ extensions; the moat; also the bloat (AI-bloat backlash driving Zed switches) | plugin runtime stub | plugin host process | 16MB+ per host | signing, permissions, sandbox mandatory | P1 | Dev |
| Remote SSH / containers / WSL | Dev where the code runs | daily for backend/enterprise | "Biggest reason teams adopt VS Code" | stub, P3 | remote transport, port-forward | server-side procs | credential handling | P3 | Remote |
| Workspace Trust | Open untrusted repos safely | occasional, high stakes | 2026 improvements (browse-then-trust); rising with agents | `workspace-trust-plus` stub | none | 2MB | core security posture | P0 | Core |
| Syntax highlighting | Read code at a glance | continuous | Absence is instantly disqualifying for daily-driver use | stub; needs decoration API | textarea decoration/gutter API (absent) | 16MB | low | P0 (blocked) | Core |
| Multi-cursor / find-replace in file | Bulk edits | hourly | Consistently in top-10 shortcuts lists | find/replace shipped in MVP (catalog stub — flag); multi-cursor blocked on caret API | caret/selection API | low | low | P1 | Core |
| Accessibility | Screen reader/keyboard-only use | continuous for affected users | 2026: signals, chat a11y; a compliance requirement for orgs | `accessibility-core` stub | SDK a11y forwarding (flagged absent for WebView) | 4MB | low | P0 | Core |
| Settings sync / profiles | Same setup everywhere | occasional | Retention feature, not acquisition | stub P3 | network + auth | low | credential/token storage | P3 | Heavy |
| Notebooks / webviews | Data science, rich docs | daily for a segment | Jupyter cited as a "stay on VS Code" niche | stub P3 | WebView (blocked) | high | webview content isolation | P3 | Heavy |

## Anti-value (what users punish)

- **Memory/CPU bloat at scale**: tsserver OOM, renderer jank in 100k-file repos.
  Velocity's bounded-everything + Process Governor is aimed exactly here.
- **AI features that can't be turned off**: the Jan 2026 HN thread (250+
  comments) on switching to Zed was about un-disable-able AI chrome. Velocity's
  `no-agents-mode` / feature-toggle-matrix is direct counter-positioning.
- **Startup time**: multi-second cold start vs Zed's sub-second.
