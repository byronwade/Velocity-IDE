# Implementation Sequence

1. Research + parity docs — **maintained**
2. Native app foundation validates/runs — **M1 done on Linux**
3. Feature catalog + generated registry — **done; catalog is authoritative**
4. Activation policy — **bounded metadata policy present**
5. Theme tokens — **done**
6. Command palette — **working for implemented commands**
7. Feature toggle matrix — **metadata/UI only**
8. Process Governor — **working for current command processes**
9. Performance HUD — **measured-or-unavailable UI + model**
10. Pipe terminal + RAM strategy — **MVP runner working; not a PTY**
11. File explorer/search/textarea editor — **M2 MVP working**
12. LSP broker scaffold — **bounded protocol; process transport blocked by SDK**
13. SCM/tasks/testing — **bounded MVP behavior; debugger not implemented**
14. Plugin runtime/registry — **not implemented**
15. Agent panel/task board — **UI/model only; no agent runtime**
16. Real terminal PTY — **bounded PTY protocol scaffold; transport blocked by SDK; MVP remains pipe `sh -c`**
17. Monaco editor island bridge — **typed backend/event scaffold; MVP remains native textarea; WebView blocked by SDK**
18. Real file/search/workspace — **bounded path open + scan + read/write done**
19. Broader Git provider — **partial MVP; status/stage/commit/review implemented**
20. Real LSP broker — **not operational**
21. Native plugin MVP — **not started**
22. Legacy VSIX research — **deferred**

## M2 notes (workspace file I/O)

- Open Folder / recent paths scan a bounded workspace via Zig 0.16 `std.Io`;
  `fixtures/acme-dashboard` is the deterministic test/demo workspace
- Caps: 256 nodes, depth 8, 16KB text read; skips `node_modules` / `.git` / vendor dirs
- Editor placeholder shows real file bytes; Monaco still deferred
- No OS folder dialog yet; typed paths and recent paths are supported

## MVP core notes

- Typed path open on launch screen (`submit_open_path`)
- Editable `<textarea>` bound to `document` TextBuffer; Save writes via `writeTextFile`
- Find + replace once/all in active document; status bar shows line/byte stats
- Recent projects on launch from prefs (path open); Copy path command
- Terminal panel runs `/bin/sh -c` via async `fx.spawn` at runtime; governor records spawn/kill
- Protocol scaffolds do not imply runtime integrations: no PTY or LSP child
  process exists, and no Monaco WebView is hosted.
- Textarea gutters still require a stable SDK gutter/decoration and
  caret/scroll contract. Disk polling now uses one keyed recurring Effects
  timer with cancellation and an explicit runtime-rejected fallback.
- See `docs/velocity/18-mvp-definition.md`
