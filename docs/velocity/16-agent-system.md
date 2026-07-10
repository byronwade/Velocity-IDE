# Agent System

## Surfaces
Composer, task cards, review/apply, autonomy slider, permissions, terminal approvals, tool registry.

## Rules
- No cloud/AI network calls in scaffold.
- No background agents unless explicitly enabled.
- Agent Mode is first-class but not startup-critical.
- MCP adapter disabled by default.
- All agent tools permissioned; terminal/shell require approval.

## Current implementation

The shell has bounded agent-facing UI/model state in
`apps/native-shell/src/model/app_model.zig`. Agent capability IDs, default
enablement, and budgets are metadata in
`apps/native-shell/src/core/feature_catalog.json`. There are no per-feature
agent modules, model adapters, background agents, or network calls yet.
