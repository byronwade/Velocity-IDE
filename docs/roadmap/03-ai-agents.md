# 03 · AI and agents

The verified frontier: Cursor 2.0 (Oct 2025) rebuilt its UI agent-centric —
delegate tasks, review outcomes, files demoted to inline pills — with parallel
agents isolated via git worktrees, a revamped multi-file diff review flow, and
a GA in-editor browser tool so agents test their own changes. Zed's answer is
open interop: a built-in agent panel speaking the Agent Client Protocol (ACP)
with MCP servers, Claude Code attachable on a consumer subscription, and fully
local models (llama.cpp/Ollama/LM Studio) as first-class providers.

Strategy for Velocity: speak the open protocols instead of building a
proprietary agent runtime, and let the Process Governor do what none of the
three ship — OS-level per-agent sandboxing.

## Todo

- [ ] P0 [TS] Agent panel v1 beyond the current mock: real task lifecycle
      (queued → running → ready-for-review → done/failed) driven by a
      governed child process; bounded task list; per-task output capture in
      the Output registry.
- [ ] P0 [TS] Provider abstraction: bring-your-own-key API providers and
      local model endpoints (llama.cpp/Ollama HTTP) behind one interface;
      no hosted-account requirement for any AI feature (local-first).
- [ ] P1 [TS] ACP client support so external agents (Claude Code, Codex,
      Gemini CLI, OpenCode) attach to the agent panel as peers rather than
      integrations Velocity must each hand-build.
- [ ] P1 [TS] MCP client support for tool servers, routed through the
      Process Governor with explicit permission prompts (plugins.permissions
      already models this).
- [ ] P1 [DIFF] Worktree-per-agent parallelism: each agent task gets an
      isolated git worktree; the Governor tracks the process tree; the SCM
      panel learns to diff/merge worktree results. Cursor ships worktrees;
      Velocity adds governed cleanup and resource caps.
- [ ] P1 [DIFF] Agent outcome review flow: a multi-file diff review surface
      (extends the existing read-only diff review) listing every file an
      agent touched, approve/revert per file — review is the bottleneck
      Cursor 2.0 named; make it Velocity's best surface.
- [ ] P2 [DIFF] OS-level agent sandboxing via the Process Governor:
      filesystem scope and network policy per agent task — the generalization
      of worktree isolation none of the three ship today.
- [ ] P2 [TS] Inline edit (selection → instruction → diff preview in place)
      once the rope engine lands; tab-completion ghost text only after
      latency instrumentation proves the <100 ms budget.
- [ ] P2 [DIFF] Agent self-testing hook: let agents run the workspace test
      task and read Problems output as structured feedback (Velocity already
      has governed task running + problem matchers — wire them to agents).
