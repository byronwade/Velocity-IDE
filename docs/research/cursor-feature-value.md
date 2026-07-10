# Cursor: What Developers Actually Value (2026)

Researched 2026-07-10. Sources: cursor.com/changelog (2.0/3.x: Composer 2.0,
Plan Mode, Cloud Agents, parallel agents), Stack Overflow 2025 (18% usage,
fastest-rising IDE), r/cursor threads, HN pricing/churn threads, eesel/locoroo
2026 review roundups.

Cursor is a VS Code fork: it inherits the entire VS Code value table
(see `vscode-feature-value.md`) and adds AI. Everything below is the *delta*
developers pay for — and the delta they complain about.

## Why developers pay for Cursor

1. **Tab (predictive multi-line autocomplete)** — the single most-cited reason.
   "Reads your mind": predicts the next *edit* (including elsewhere in the
   file), not just the next token. Continuous-frequency value.
2. **Inline edit (Cmd+K)** — select code, describe change, get a diff in place.
3. **Agent/Composer with plan → apply → review loop** — multi-file changes with
   a reviewable diff set and checkpoints to roll back.
4. **Codebase indexing (embeddings)** — "@codebase" context; the agent knows
   your repo.
5. **Frictionless adoption** — it *is* VS Code: same extensions, keybindings,
   settings import. Switch cost ≈ zero. This matters for Velocity: import paths
   lower switch cost more than any feature.
6. **Parallel agents (3.x)** — up to 8 agents in worktrees/remote VMs; plan with
   one model, build with another.

## Feature value table (delta over VS Code)

| Feature | User problem | Freq | Why valued | Velocity status | SDK requirement | Mem/proc | Security | Priority | Bucket |
|---|---|---|---|---|---|---|---|---|---|
| Tab autocomplete | Typing is the bottleneck | continuous | #1 cited value; "worth $20 alone" | `inline-suggestions` stub | caret/decoration API for ghost text (absent) + network | 16MB + net | code leaves machine → consent UI | P1 (blocked + AI-Later) | AI-Later |
| Inline agent edit (Cmd+K) | Small transformations w/o context switch | hourly | Lowest-friction AI entry point | `inline-agent-edit` stub | selection API + diff apply | low | prompt/code egress | P1 | AI-Later |
| Agent / Composer | Multi-file changes from intent | daily | The headline; plan mode + parallel plans (3.x) | `agent-composer` + task board stub (UI model only) | network; worktrees for parallel | 1 proc per agent run | arbitrary edits → review gate mandatory | P0 of AI phase | AI-Later |
| Agent review/apply/checkpoints | Trust but verify AI edits | daily (with agent) | Checkpoints/rollback repeatedly praised; diff-first review is the trust maker | `agent-review`/`agent-apply`/`agent-checkpoints` stub | none beyond editor diff (diff editor **working**) | low | THE safety layer | P0 of AI phase | AI-Later |
| Codebase indexing | Agent needs repo context | background | Enables everything; also the #1 perf complaint | `agent-indexer` stub | file read + optional embedding service | 500MB–1GB extra RAM reported — cautionary tale | index contents = source code copy | P1 | AI-Later |
| Terminal command approval | Agents run commands | daily (with agent) | Users demand approval gates; Cursor's are considered decent | `agent-terminal-approval` stub | PTY/pipe runner | low | core agent-era security | P0 of AI phase | AI-Later |
| Cloud/background agents | Long tasks off the laptop | weekly | Praised, but drove bill shock | `agent-cloud-adapter` stub | network | remote | remote code execution + billing | P2 | AI-Later |
| Privacy mode | Code must not train models | continuous (policy) | Enterprise requirement; SpaceX-acquisition privacy backlash shows fragility | n/a (Velocity ships network-off by default) | none | none | differentiator: local-first, telemetry off | P0 posture | Core |

## Anti-value (Cursor's churn drivers → Velocity lessons)

- **Opaque pricing / billing shock**: ~500→~225 effective requests at same $20;
  single-day plan depletion; $1,800/mo anecdotes → mass migration to Claude
  Code. Lesson: metering must be visible and bounded (fits Velocity budgets UI).
- **Resource cost**: +0.5–1GB RAM over stock VS Code (embeddings); 100k-file
  repos "lag hard". Lesson: index must be bounded, optional, evictable
  (`codebase-index-health`, `memory-pressure-mode`).
- **Privacy trust is brittle**: one acquisition rumor moved users. Local-first
  adapters (`agent-local-adapter`) are a moat.
- **Fork tax**: Cursor trails upstream VS Code releases; users notice.

## Implication for Velocity

Rank AI features honestly high on market evidence (18% and rising, top revenue
in dev tools) but bucket ALL of them AI-Later per plan. What Velocity should
build *now* from Cursor's playbook: the **review/apply/permission substrate**
(diff review is already working; approval gates are native UI) so the AI phase
lands on rails, not on trust debt.
