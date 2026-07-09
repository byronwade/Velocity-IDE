# Terminal RAM and Process Management

## Goals
Near-instant terminal panel; low idle RAM; no leaked shells.

## Defaults (Velocity)
| Setting | Value |
|---|---|
| Default scrollback | 2,000 lines |
| Hard max scrollback | 10,000 lines |
| Buffer | Segmented / ring — not one giant string |
| Rendering | Visible viewport only |
| Images / ligatures | Off by default |
| Shell integration | Off until first command (optional Dev) |
| Search index | Lazy on terminal-find open |
| Serialize/export | Explicit only |
| Profile / env detection | Cached; no login probing before first paint |
| Prewarm shells | Off by default |

## Process ownership
- PTY spawned only via Process Governor (`apps/native-shell/src/processes/`).
- Close terminal → kill process tree unless user detaches.
- Task terminals: reuse or auto-close by policy.
- Inactive terminals: freeze/suspend where OS allows.
- Memory estimate shown in Performance HUD + Terminal Memory Inspector.

## VS Code comparison
This fork defaults `terminal.integrated.scrollback` to **1000** and pre-allocates for smoothness (`terminalConfiguration.ts`). Velocity keeps a higher default for usability but **hard-caps** and uses a ring buffer to avoid unbounded growth.

## Status
Scaffold: mock terminal lines in shell UI; real PTY later.
