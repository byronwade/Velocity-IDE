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

## Round 2: hover / definition / completion position contract

The editor's textarea exposes no caret, so all position-based requests
use the documented focus-line contract (LSP positions 0-based; the
editor's focus line 1-based, default 1 when unset):

- **Hover** (`hover_info`): line = focus line, character = the line's
  first non-space byte. Result renders scrubbed plain text (code fences
  dropped, inline backticks and heading markers stripped) in a bounded
  panel (1 KiB, 10 display lines) under the breadcrumb.
- **Definition** (`go_to_definition`): line = focus line, character =
  the byte offset of the Find/Symbol query on that line when present,
  else the first non-space byte. In-workspace targets navigate like a
  search hit ("Definition via LSP"); cross-root targets surface an
  honest toast. When the session is not running the flow falls back to
  the heuristic text search ("Definition via text search").
- **Completion** (`completion_at_cursor`): line = focus line, character
  = the line's byte length (end of line), so the server completes the
  trailing prefix. The overlay shows the top 12 items; selecting one
  targets the END of the captured focus line — the trailing identifier
  word ([A-Za-z0-9_$]+) is replaced when it prefixes the insert text,
  otherwise the text is appended. Caret-precise insertion is
  intentionally NOT claimed.

Byte offsets are used where LSP specifies UTF-16 code units; they agree
on ASCII lines (honest approximation for v2). Request ids are tracked
in a bounded registry (`lsp_session.Runtime.tracked`, 8 slots) and
expire through the session's deadline sweep with per-kind timeout
toasts.
