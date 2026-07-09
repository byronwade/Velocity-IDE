# Velocity IDE

This repository contains:

1. The original **VS Code / Code-OSS fork** under `src/`, `extensions/`, etc. — reference, compatibility bunker, performance baseline. **Do not treat it as the product we ship.**
2. The new **Velocity** native IDE experiment under `apps/native-shell/`.

## Status (M1 scaffold)

| Check | Status |
|---|---|
| Docs (`docs/velocity/`) | Present |
| Cursor rules (`.cursor/rules/velocity-*.mdc`) | Present |
| Native SDK app | `apps/native-shell` |
| `native check` | Pass |
| `native test` | Pass (7/7) |
| `native build` | Pass on Linux with GTK4 + WebKitGTK 6.0 |
| Interactive window | Launches; launch screen + mock IDE chrome |

Codename **Velocity** is temporary and rename-ready.

## Run

```bash
npm install -g @native-sdk/cli   # or: npm install --prefix .tools @native-sdk/cli
# Linux:
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev

cd apps/native-shell
npm run check && npm run test && npm run build
npm run dev
# or: ./zig-out/bin/velocity-ide
```

## Docs

Start at `docs/velocity/00-master-plan.md` and `docs/velocity/10-running-the-app.md`.

## Next milestones

1. Real folder open / workspace core
2. Monaco editor island after first paint
3. Native terminal PTY
4. LSP broker
5. Plugin permission enforcement

Do **not** rewrite the Electron workbench for Velocity features in this phase.
