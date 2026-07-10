# 05 · Language intelligence

Zed's verified stance: Git, LSP, and formatters belong in the editor core,
not extensions — "batteries included" is why a thin extension surface is
viable. This is table stakes for Velocity's first run: working language
smarts with zero plugin installs.

Existing assets: LSP jsonrpc/broker/server_process scaffolding, problem
matchers, outline, go-to-def heuristics, format-on-save toggles (trim
trailing, final newline).

## Todo

- [ ] P0 [TS] Finish the LSP transport: spawn a real server through the
      Process Governor (lease + reaper), initialize, didOpen/didChange with
      rope snapshots, and surface diagnostics into the Problems store.
- [ ] P0 [TS] Diagnostics in the editor: squiggle/underline spans via stable
      anchors; gutter markers; problems count in the status bar.
- [ ] P1 [TS] Hover, go-to-definition, and completions from LSP (replace the
      current heuristic go-to-def when a server is attached; keep the
      heuristic as offline fallback).
- [ ] P1 [TS] Syntax highlighting: tree-sitter (or SDK-provided grammar
      pipeline) driven from rope snapshots on a background thread — the
      concurrency story the rope exists for.
- [ ] P1 [TS] Formatter integration: format-on-save through governed
      processes with per-language config; zero-config defaults for the
      obvious ecosystems (zig fmt, prettier, gofmt, rustfmt).
- [ ] P2 [TS] Per-language server registry with lazy activation policy
      (feature catalog already models activation) and a HUD row for language
      server memory/process counts.
- [ ] P2 [DIFF] Diagnostics-as-agent-context: one command to hand the
      current file's diagnostics + excerpt to the agent panel.
