# Agent Composer

- **id:** `feature.agent-composer`
- **mode:** `agent`
- **status:** `stub`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `24`
- **maxProcesses:** `0`
- **activation:** `onAgentStart`, `onViewVisible:agents`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.
