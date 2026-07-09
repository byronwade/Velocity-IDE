# LSP Broker Notes

## Boundary

- Native shell talks only to the LSP broker.
- Broker manages external language server processes.
- Broker enforces workspace scope.
- Broker will measure CPU/memory later.
- Broker does **not** depend on the VS Code extension host.

## Milestone plan

1. Stub (this directory).
2. JSON-RPC framing over stdio to one server (TypeScript).
3. Diagnostics → workspace core.
4. Completions / hover / go-to-def.
5. Multi-server + crash isolation.
