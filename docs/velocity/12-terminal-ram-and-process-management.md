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
The external [Microsoft VS Code terminal baseline](https://github.com/microsoft/vscode/tree/main/src/vs/workbench/contrib/terminal)
has historically defaulted `terminal.integrated.scrollback` to **1000**.
Velocity keeps a higher default for usability but **hard-caps** and uses a ring
buffer to avoid unbounded growth.

## Status
Prototype: the non-interactive pipe runner captures command output. A bounded
PTY session/output/input/resize protocol now exists, but its transport is
explicitly unavailable and no interactive shell is claimed. It is unblocked
only by an SDK-supported cross-platform PTY with streamed stdin/stdout, resize,
cancellation/exit, and process-tree lifecycle hooks. Existing contiguous pipe
line storage remains separate to avoid regressing borrowed UI/diagnostic data.
