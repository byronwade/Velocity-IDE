# Velocity Native Shell

Codename **Velocity** (rename-ready). Native SDK app shell for the new IDE.

## Requirements

- Node.js 20+
- `@native-sdk/cli` (`npm install -g @native-sdk/cli` or local install)
- Zig toolchain (CLI can download the pinned version)

## Commands

```bash
# from apps/native-shell
npm run check    # validate markup + app.zon
npm run test     # headless UI tests
npm run dev      # open native window (macOS primary; Linux/Windows supported by SDK)
npm run build    # ReleaseFast binary
npm run perf-smoke
```

Or with the CLI directly:

```bash
native check
native test
native dev
native build
```

## Layout

| Path | Role |
|---|---|
| `src/app.native` | Declarative IDE shell UI |
| `src/main.zig` | Window / tokens / shortcuts wiring |
| `src/model/app_model.zig` | TEA model + mock data |
| `src/theme/tokens.zig` | Design tokens |
| `src/plugins/` | Manifest + permissions stubs |
| `src/registry/` | Registry preview stub |
| `src/lsp/` | LSP broker boundary |
| `src/terminal/` | Terminal stub + pty notes |
| `src/bridge/` | Editor island / Monaco notes |
| `src/perf/` | Perf snapshot struct |

## Product docs

See `/docs/velocity/`.

## Legal / design

Cursor and Vercel are inspiration only. No copied logos, assets, CSS, or trade dress.
