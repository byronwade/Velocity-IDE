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
| W1a document ceiling 16 KiB → 256 KiB | orchestrator | `native test` incl. new large-doc test, strict check, build, explorer smoke | green |
| W1a store-honesty fix: FileTooLarge open no longer clobbers editor/tab state (size preflight before mutation) | orchestrator | regression assertions in workspace_store test | green |
| W1b operation-based undo history (reverse patches + word-grouped typing, memory ∝ edits) | orchestrator | 9 module tests incl. memory-proportionality proof | green |
| W6 ripgrep engine (explicit search-panel toggle, honest fallback, e2e skip-without-rg + rg installed in CI) | rg lane + orchestrator | 18 adapter tests + app toggle test + screenshot | green |
| W9 git branches: bounded list, `git switch`/`switch -c` via literal argv, option-injection name gate, dirty-editor refusal, post-switch tab-preserving rescan | orchestrator | real-repo module round-trip test (incl. git's own conflicting-change refusal), 279/279, strict, screenshot | green |
| Catalog reconciliation: 26 verified status corrections (10→working incl. git-branches, 16→prototype), evidence per line in gap register | QA lane | features:generate + full suite | green |
| LSP sidecar broker SPIKE: Content-Length↔NDJSON re-framing, token-auth POST input, chunk reassembly, process-group kill; **real typescript-language-server handshake validated** | LSP lane | 18 unit tests + spike.sh 16/16 PASS | proven (sidecar/) |

## Implementing

| Item | Owner | Files owned | Verification | Next action |
|---|---|---|---|---|
| — (between slices) | | | | pick from queue |

## Queue (ranked)

| Rank | Item | Class | Dependency |
|---|---|---|---|
| 1 | LSP broker productionization: `--liveness=http` heartbeat (SDK closes child stdin), TERM→KILL escalation, then governed app integration + didOpen/diagnostics vertical | SPIKE→READY | sidecar spike (done) |
| 2 | Command surface completion (registry coverage + fuzzy command search) | PARTIAL | none |
| 3 | Git: stage/unstage hunks, guarded discard-file confirm flow, stash | READY | branch slice (done) |
| 4 | Workspace Trust Plus (granular read/write/run/net) | READY | none |
| 5 | PTY vertical slice via sidecar broker (Linux openpty first) | SPIKE | broker (proven) |
| 6 | File watcher spike (SDK FS events absent → tiered bounded polling exists; formalize) | SPIKE | none |
| 7 | Language registry (extensions/comments/brackets per language) | READY | none |
| 8 | Editor island WebView spike (web_panes + bridge invoke; focus/IME on WebKitGTK) | SPIKE | none |

## Blocked

| Item | Evidence | Unblock criteria |
|---|---|---|
| In-textarea rich styling (syntax highlighting, multi-cursor rendering) | textarea renders a single style run (sdk-capability-report.md) | WebView editor island (queue #8) or SDK styled-run API |
| Synced line-number gutter in the markup app | `on-scroll` schema-restricted to `<scroll>`; no textarea scroll binding (native-sdk-blockers.md 2026-07-10 verdict) | markup textarea on-scroll + offset binding, or raw-widget escape |
| Windows/macOS PTY | broker spike is Linux openpty first | ConPTY adapter + platform validation |

## Notes

- Document-engine structure decision: the SDK textarea owns keystroke editing
  against a contiguous comptime-capacity `TextBuffer`, so piece-table/rope
  storage is deferred until a custom editor surface exists; heap-resident
  singletons hold per-tab working copies (exact behavior documented in
  workspace_store.zig). Revisit at the editor-island wave.
- Scratch buffers that scale with `max_editor_bytes` must be transient heap,
  never stack arrays-of-tabs (enforced pattern; see rescanPreserveTabs).
