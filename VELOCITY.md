# Velocity IDE

This repository is the standalone Velocity native IDE. Microsoft VS Code is
used only as an external research reference.

## Status

| Area | Status |
|---|---|
| Native SDK shell | Check/test/build pass on Linux; other platforms are not CI-validated |
| Automated coverage | 252 native tests; eight end-to-end smoke scripts |
| Workspace file I/O (M2) | Fixture + typed path open, bounded scan, text read |
| Edit + Save (MVP) | Native textarea + disk write (Cmd+S) |
| New / Rename / Delete | Explorer file ops + rescan |
| Explorer collapse | Per-folder and all-folder controls; filter temporarily reveals matches |
| Find + Quick Open | In-doc find; Cmd+P file filter |
| Replace + Copy path | Replace once/all; copy active path to toast |
| Prefs + Recent | Theme / last path / panels / recent / auto-save / find-case |
| Document stats | Status bar line + byte counts |
| Breadcrumb | Active relative path in editor header |
| Problems | Marker + terminal/test diagnostics, severity/source filters |
| Diff review | Read-only, bounded line review for saved and staged/unstaged Git changes; not an editable diff editor |
| Snippets | Versioned, bounded workspace/user literal snippets; no dynamic placeholders |
| Editor transforms | Toggle comment, indent/outdent, reopen closed tab |
| Search (MVP) | Bounded in-process workspace text search |
| SCM (MVP) | Lazy `git status` / branch via governor |
| Terminal (MVP) | Async `fx.spawn` pipe runner (sync fallback in tests) |
| Tasks / Tests (MVP) | npm + tasks.json + Make detection; governed run/stop/rerun |
| Run profiles | Bounded `.velocity/launch.json` command profiles; not debugger configurations |
| Output (MVP) | Bounded labeled task/test terminal mirror |
| Feature metadata | Canonical 200-entry `src/core/feature_catalog.json`; no per-feature source directories |
| Feature registry + activation policy | Generated `src/core/feature_registry.zig` plus bounded activation policy |
| Process Governor | Tracks terminal / search / scm runs |
| Performance HUD | Reports measured values or `n/a`; no startup/RSS budget claim yet |
| Research docs | `docs/velocity/11-*.md` … `18-*.md` |

Codename **Velocity** is temporary and rename-ready.

## Run

```bash
npm install
npm run check && npm run build
npm run dev
```

## Docs

- Roadmap todo list: `docs/roadmap/README.md`
- Plan: `docs/velocity/00-master-plan.md`
- Research: `docs/velocity/11-vscode-feature-parity-research.md`
- Matrix: `docs/velocity/14-feature-parity-matrix.md`
- Sequence: `docs/velocity/17-implementation-sequence.md`
- Runbook: `docs/velocity/10-running-the-app.md`

## Next

1. OS folder dialog (`showOpenDialog`) when the runtime hook is wired
2. Operational rich editor island after first paint
3. Real PTY terminal to replace the pipe runner
4. LSP transport and broader Git provider behavior

MVP definition: `docs/velocity/18-mvp-definition.md`

VS Code reference: https://github.com/microsoft/vscode
