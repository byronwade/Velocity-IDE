# Velocity Roadmap

A prioritized, working todo list for making Velocity a top-of-the-line native
IDE. Built from an adversarially verified deep-research pass (July 2026) over
the three leading editors — Cursor 2.0+, Zed, and VS Code — plus Velocity's
own architecture docs. Every claim cited here survived 3-voter adversarial
verification unless marked otherwise; vendor performance numbers are treated
as positioning, not fact.

## How to use this folder

Work top-down within a file, and roughly in file order across the folder.
Check items off in place (`[x]`) and note the landing commit/PR beside them.
Items carry two tags:

- **[TS]** table stakes — users assume it; absence reads as broken.
- **[DIFF]** differentiator — where Velocity can beat Cursor/Zed/VS Code.

Priorities: **P0** (foundation, blocks other work) · **P1** (needed for a
credible 1.0) · **P2** (post-1.0 or opportunistic).

## Files

| File | Theme |
|---|---|
| `01-editor-core.md` | Text engine: rope/SumTree, snapshots, CRDT anchors |
| `02-performance.md` | Budgets, measurement discipline, startup/latency |
| `03-ai-agents.md` | Agent panel, ACP/MCP interop, parallel agents |
| `04-workbench-ux.md` | Design system, chrome, palette, diff, terminal |
| `05-language-intelligence.md` | LSP, syntax, formatters, diagnostics |
| `06-git-and-collab.md` | Built-in Git UX; CRDT collaboration later |
| `07-extensibility.md` | Plugin surface, registry, security |
| `99-open-questions.md` | Unresolved research questions to answer before betting |

## The one-paragraph strategy

Zed proves the native bar (SumTree rope, CRDT-native buffers, GPU UI at an
8.33 ms frame budget, batteries-included Git/LSP); Cursor 2.0 defines the
AI-first frontier (low-latency in-house model, agent-centric UI, parallel
agents isolated in git worktrees, in-editor browser for agent self-testing);
VS Code supplies the cautionary tales (line-array memory blowups, the
JS↔native boundary tax that forced them to stay in JavaScript). Velocity's
Zig-native, process-governed stack has no managed-runtime boundary, so
Zed-class performance is the credible target — and process governance can
generalize Cursor's worktree isolation into OS-level agent sandboxing, which
none of the three ship today.
