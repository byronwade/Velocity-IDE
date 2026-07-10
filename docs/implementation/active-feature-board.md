# Active Feature Board

Live queue for the daily-driver implementation waves. One integration-changing
patch touches shared shell/model files (`app.native`, `app_model.zig`,
registries) at a time; lane agents deliver standalone modules + tests that the
orchestrator integrates.

Baseline (2026-07-10, local Linux runner): 252/252 native tests, strict check
green, `features:check` green, ReleaseFast build green after
GTK4/WebKitGTK install, smoke green under `xvfb-run`. Catalog: 200 features —
17 working / 4 prototype / 179 stub. Zig 0.16.0 installed via the PyPI
`ziglang` wheel (ziglang.org egress-blocked; see native-sdk-blockers.md).

Research inputs: `docs/product/velocity-feature-priority.md` (ranked queue),
`docs/product/velocity-gap-register.md` (18 catalog inaccuracies),
`docs/velocity/sdk-capability-report.md` (blocker verdicts: gutter SPIKE-ready
today; LSP + PTY feasible via governed sidecar broker; no SDK upgrade needed).

## Complete

| Item | Owner | Verification | Result |
|---|---|---|---|
| W0 baseline + toolchain unlock (Zig via PyPI wheel, xvfb smokes) | orchestrator | `native test`, `native build`, explorer smoke | 252/252, build ok, smoke ok |
| W1a document ceiling 16 KiB → 256 KiB | orchestrator | `native test` (253/253 incl. new large-doc test), strict check, build, explorer smoke | green |
| W1a store-honesty fix: FileTooLarge open no longer clobbers editor/tab state (size preflight before mutation) | orchestrator | new regression assertions in workspace_store test | green |

## Implementing

| Item | Owner | Files owned | Verification | Next action |
|---|---|---|---|---|
| Line-number gutter synced to textarea scroll (SDK spike 1: model-owned scroll + textGeometryForWidget) | orchestrator | app.native, app_model.zig, workspace/editor_view.zig | native test + new gutter tests + screenshot | implement |

## Queue (ranked)

| Rank | Item | Class | Dependency |
|---|---|---|---|
| 1 | Ripgrep-backed workspace search (governed single-shot spawn) | READY | standalone adapter module first |
| 2 | LSP sidecar broker spike (stdio re-framing to NDJSON + POST input) | SPIKE | standalone broker exe + framing tests |
| 3 | Command surface completion (registry coverage + fuzzy command search) | PARTIAL | none |
| 4 | Git core completion (branches, stage/unstage file, guarded discard) | READY | argv-git pattern (proven) |
| 5 | Catalog reconciliation (18 wrong statuses; add `partial` status) | READY | gap register §A |
| 6 | Workspace Trust Plus (granular read/write/run/net) | READY | none |
| 7 | PTY vertical slice via sidecar broker (Linux openpty first) | SPIKE | broker from rank 2 |
| 8 | Undo/redo: diff-based entries replacing full-text snapshots | READY | W1a (done) |
| 9 | File watcher spike (SDK FS events else tiered bounded polling) | SPIKE | none |
| 10 | Editor island WebView spike (web_panes + bridge invoke) | SPIKE | focus/IME validation on WebKitGTK |

## Blocked

| Item | Evidence | Unblock criteria |
|---|---|---|
| In-textarea rich styling (syntax highlighting, multi-cursor rendering) | textarea renders a single style run (sdk-capability-report.md) | WebView editor island (queue #10) or SDK styled-run API |
| Windows/macOS PTY | broker spike is Linux openpty first | ConPTY adapter + platform validation |

## Notes

- Document-engine structure decision: the SDK textarea owns keystroke editing
  against a contiguous comptime-capacity `TextBuffer`, so piece-table/rope
  storage is deferred until a custom editor surface exists; heap-resident
  singletons hold per-tab working copies (exact behavior documented in
  workspace_store.zig). Revisit at the editor-island wave.
- Scratch buffers that scale with `max_editor_bytes` must be transient heap,
  never stack arrays-of-tabs (enforced pattern; see rescanPreserveTabs).
