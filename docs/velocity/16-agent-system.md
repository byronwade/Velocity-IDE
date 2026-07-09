# Agent System

## Surfaces
Composer, task cards, review/apply, autonomy slider, permissions, terminal approvals, tool registry.

## Rules
- No cloud/AI network calls in scaffold.
- No background agents unless explicitly enabled.
- Agent Mode is first-class but not startup-critical.
- MCP adapter disabled by default.
- All agent tools permissioned; terminal/shell require approval.

## Modules
Under `apps/native-shell/src/features/agent-*` and related velocity modules.
