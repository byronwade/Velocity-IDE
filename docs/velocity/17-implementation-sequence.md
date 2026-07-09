# Implementation Sequence

1. Research + parity docs — **this pass**
2. Native app scaffold validates/runs — **M1 done**
3. Feature registry — **scaffold**
4. Activation policy — **scaffold**
5. Theme tokens — **done**
6. Command palette — **done (mock)**
7. Feature toggle matrix — **UI scaffold this pass**
8. Process Governor — **scaffold**
9. Performance HUD — **UI + model**
10. Terminal scaffold + RAM strategy — **docs + mock**
11. File explorer/search/editor placeholders — **M2 + MVP edit/save**
12. LSP broker scaffold — **stub**
13. SCM/debug/tasks/testing placeholders — **UI**
14. Plugin runtime/registry placeholders — **stub**
15. Agent panel/task board — **mock**
16. Real terminal PTY — **MVP: pipe `sh -c` runner (not PTY)**
17. Monaco editor island bridge — **MVP: native textarea first**
18. Real file/search/workspace — **path open + scan + read/write**
19. Real Git provider
20. Real LSP broker
21. Native plugin MVP
22. Legacy VSIX research only

## M2 notes (workspace file I/O)

- Open Folder / recent `acme-dashboard` scans `fixtures/acme-dashboard` via Zig 0.16 `std.Io`
- Caps: 256 nodes, depth 8, 16KB text read; skips `node_modules` / `.git` / vendor dirs
- Editor placeholder shows real file bytes; Monaco still deferred
- No OS folder dialog yet — fixture path only

## MVP core notes

- Typed path open on launch screen (`submit_open_path`)
- Editable `<textarea>` bound to `document` TextBuffer; Save writes via `writeTextFile`
- Find + replace once/all in active document; status bar shows line/byte stats
- Recent projects on launch from prefs (path open); Copy path command
- Terminal panel runs `/bin/sh -c` via async `fx.spawn` at runtime; governor records spawn/kill
- See `docs/velocity/18-mvp-definition.md`
