# Terminal

- **id:** `feature.terminal`
- **mode:** `core`
- **status:** `prototype` — pipe runner works; interactive PTY transport is SDK-blocked
- **startupAllowed:** `false` — panel chrome may show; PTY only on explicit open
- **memoryBudgetMB:** `32`
- **maxProcesses:** `1`
- **scrollback default:** 2000 / hard max 10000 (ring buffer)

## Rules

- Spawn only via Process Governor.
- Close kills process tree unless detached.
- See `docs/velocity/12-terminal-ram-and-process-management.md`.

## Honest boundary

`terminal/pty_session.zig` defines a bounded output ring, input queue, resize
commands, and typed lifecycle events. Its transport availability is explicitly
`unavailable`; it does not spawn a shell. The existing non-interactive
pipe-based command runner remains unchanged. Its contiguous line storage is
kept separate because diagnostics and UI currently borrow that layout; swapping
it for the PTY ring would risk a runtime regression.

Interactive terminal support is unblocked only when the SDK provides a
cross-platform PTY spawn API, streaming stdin/stdout and resize events, and
process-tree close/cancellation integrated with Effects and Process Governor.
