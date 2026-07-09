# Terminal Performance Plan

## Goals

- Terminal panel opens near-instantly in Core Mode.
- No expensive login-shell probing on workbench startup.
- xterm addons load only when needed.
- Shell integration deferred unless enabled.

## Current architecture

| Layer | Path | Notes |
|---|---|---|
| Contrib aggregator | `contrib/terminal/terminal.all.ts` | Stock imports all terminalContrib modules |
| Core aggregator | `contrib/terminal/terminal.core.ts` | Lean set (no chat/voice/WSL tip) |
| Instance | `browser/terminalInstance.ts` | Creates xterm + process |
| xterm wrapper | `browser/xterm/xtermTerminal.ts` | Addon orchestration |
| Addon importer | `browser/xterm/xtermAddonImporter.ts` | **Already lazy** via dynamic import |
| PTY host | `platform/terminal/node/ptyHostMain.ts` | Separate process |
| Shell integration | `platform/terminal/common/xterm/shellIntegrationAddon.ts` | Eager today when enabled |

### Addons (package.json)

`clipboard`, `image`, `ligatures`, `progress`, `search`, `serialize`, `unicode11`, `webgl`

Load behavior today:

- Shell integration: constructed with terminal (when setting enabled)
- Serialize / ligatures / image: on demand in xtermTerminal
- WebGL: when GPU acceleration path enables it

## Core Mode defaults

| Setting / flag | Core default |
|---|---|
| `terminal.integrated.shellIntegration.enabled` | `false` |
| `terminal.integrated.enableImages` | `false` |
| `terminal.integrated.fontLigatures.enabled` | `false` |
| `terminal.integrated.gpuAcceleration` | `off` |
| `terminal.imageAddon` feature | disabled |
| `terminal.ligaturesAddon` | disabled |
| `terminal.serializeAddon` | disabled until needed |
| `terminal.chatContrib` | disabled |
| Contrib import set | `terminal.core.ts` |

## Action items

1. **Done:** lean `terminal.core.ts`; Core defaults disable shell integration / images / ligatures / GPU.
2. Cache resolved shell profiles after first terminal open; avoid re-detect on every window.
3. Defer environment resolution / login shell probing until first terminal create.
4. Add `terminal.integrated.fastMode` (future) bundling the above.
5. Benchmarks: `scripts/perf-fork/terminal.mjs` records open timing marks when available.

## Measurement

```bash
npm run perf-fork
# inspect .perf-fork/latest.json → metrics.terminal
```

Target: terminal show → ready &lt; 100ms local PTY attach on warm host (excluding shell init).

## Rollback

`--perf-fork-enable=terminal.shellIntegration,terminal.gpuAcceleration` or Developer/Compat mode.
