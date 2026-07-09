# LSP Broker

- **id:** `feature.lsp-broker`
- **mode:** `core`
- **status:** `prototype` — protocol scaffold; runtime transport blocked by SDK
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `16`
- **maxProcesses:** `0`
- **activation:** `onLanguage`, `onFileOpen`

## Rules

- Lazy by default unless `startupAllowed`.
- Child processes only via Process Governor.
- Feature is killable via Feature Toggle Matrix.
- See `docs/velocity/14-feature-parity-matrix.md`.

## Honest boundary

`lsp/jsonrpc.zig` and `lsp/broker.zig` provide bounded Content-Length framing,
request IDs, sessions, pending requests, and diagnostic snapshots. They are
transport-independent and do not spawn or claim a language server.

Runtime LSP is unblocked only when the SDK supports long-lived child processes
with stdin/stdout streams, incremental reads, write backpressure,
cancellation/exit events, and process-tree ownership that can be integrated
with the Process Governor and Effects lifecycle.
