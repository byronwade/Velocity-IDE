# Velocity IDE

This repository contains:

1. The original **VS Code / Code-OSS fork** under `src/`, `extensions/`, etc. — reference, feature oracle, compatibility bunker, performance baseline. **Not the product we ship.**
2. The new **Velocity** native IDE under `apps/native-shell/`.

## Status

| Area | Status |
|---|---|
| Native SDK mock shell | Runs (`native check` / `test` / `build`) |
| Feature modules | 200 stubs under `src/features/` |
| Feature registry + activation policy | Scaffold |
| Process Governor | Scaffold (no OS spawn yet) |
| Performance HUD / Feature Matrix | UI + mock metrics labeled **mock** |
| Research docs | `docs/velocity/11-*.md` … `17-*.md` |

Codename **Velocity** is temporary and rename-ready.

## Run

```bash
npm install -g @native-sdk/cli   # or: npm install --prefix .tools @native-sdk/cli
# Linux:
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev

cd apps/native-shell
npm run check && npm run test && npm run build
npm run dev
```

## Docs

- Plan: `docs/velocity/00-master-plan.md`
- Research: `docs/velocity/11-vscode-feature-parity-research.md`
- Matrix: `docs/velocity/14-feature-parity-matrix.md`
- Sequence: `docs/velocity/17-implementation-sequence.md`
- Runbook: `docs/velocity/10-running-the-app.md`

## Next

1. Real folder open / workspace core  
2. Monaco editor island after first paint  
3. Native terminal PTY via Process Governor  
4. Git provider + LSP broker  

Do **not** rewrite the Electron workbench for Velocity features in this phase.
