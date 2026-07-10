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
| W4 **operational LSP vertical**: Settings toggle (default off) → governed broker spawn on supported-file open → initialize/didOpen/didChange/didSave/didClose → publishDiagnostics in the Problems panel; heartbeat liveness, TERM→KILL escalation, honest unavailable states. Two runtime-Io defects (PATH_MAX realpath contract) found by driving the real app and fixed | LSP lane + orchestrator | 348/348 tests; lsp-smoke PASS end-to-end with real typescript-language-server (SKIPs honestly without it) | green |
| W11 fuzzy command search (subsequence ranking, 'gts' → Go to Symbol) | orchestrator | registry + app tests | green |
| W3 language registry (display/LSP ids/comments/server candidates); transform caps scaled to editor ceiling (defect fix) | orchestrator | registry tests + 100 KiB toggle round-trip | green |
| W9b git stash (push/list/apply/pop/drop, dirty-editor gate, rescan) | orchestrator | real-repo round-trip test | green |
| W8 PTY spike: real openpty broker, interactive echo, resize, session-sweep reaping | terminal lane | 41 unit tests + pty-spike PASS | proven |
| W8 **interactive terminal vertical**: explicit switch → governed PTY broker → persistent shell state, ANSI-stripped bounded ring, exit codes, Stop/Restart, clean teardown; pipe runner stays default/fallback | terminal lane + orchestrator | 400/400 tests; pty-terminal-smoke PASS (state persistence proven); terminal-smoke green | green |
| CI: smoke (lsp) suite green after build-order, version-pin, torn-read fixes | orchestrator | CI run on latest completed head | green |
| W9c hunk-level stage/unstage/discard (bounded patch engine, real-repo proof, double-press discard + dirty gate) | git lane + orchestrator | 412/412; hunk_patch 11 tests + applyHunk repo test | green |
| W5 directory watcher: per-dir mtime baseline + budgeted round-robin poll → auto explorer refresh; app-write masquerade prevented via rescan re-baseline | orchestrator | 414/414; module tests at nested depth | green |
| Branch fully green in CI at 513e1c7 (CI + Smoke incl. lsp + Screenshots on three consecutive heads) | — | GitHub Actions | green |
| W4r2 **LSP hover + definition (working) and completion (prototype, honest insertion contract)**: focus-line positions, bounded extractors, request tracking with timeout toasts; manual real-server drive verified all three | LSP lane + orchestrator | 430/430; lsp-smoke PASS incl. hover scenario | green |

## Implementing

| Item | Owner | Files owned | Verification | Next action |
|---|---|---|---|---|
| — (between slices) | | | | pick from queue |

## Queue (ranked)

| Rank | Item | Class | Dependency |
|---|---|---|---|
| 1 | Terminal round 2: resize wiring, per-command exit codes (OSC-133), ANSI rendering | PARTIAL | interactive vertical (done) |
| 2 | Workspace Trust Plus (granular read/write/run/net) | READY | needs per-workspace persistence design (prefs are app-global today) |
| 3 | Editor island WebView spike (web_panes + bridge invoke; focus/IME on WebKitGTK) | SPIKE | none |
| 4 | Multibuffer data model (read-only slice over search/diagnostic results) | READY | none |
| 5 | LSP round 3: references, rename, formatting; UTF-16 position mapping for non-ASCII lines | READY | round 2 (done) |

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
