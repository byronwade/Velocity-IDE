# Terminal

- **id:** `feature.terminal`
- **mode:** `core`
- **status:** `stub` (mock UI; real PTY later)
- **startupAllowed:** `false` — panel chrome may show; PTY only on explicit open
- **memoryBudgetMB:** `32`
- **maxProcesses:** `1`
- **scrollback default:** 2000 / hard max 10000 (ring buffer)

## Rules

- Spawn only via Process Governor.
- Close kills process tree unless detached.
- See `docs/velocity/12-terminal-ram-and-process-management.md`.
