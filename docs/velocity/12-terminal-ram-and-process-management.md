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
Working (Linux): the terminal panel's explicit "Interactive shell" switch runs
a REAL PTY session through the governed sidecar broker
(`apps/native-shell/sidecar/pty_broker.zig` + `src/terminal/pty_runtime.zig`):
shell state persists across commands (cd, env vars, functions), output streams
into the bounded 2,000-line ring with ANSI sequences STRIPPED (colors/cursor
addressing are not rendered yet — an honest limitation), the shell's exit code
surfaces in the scrollback, and panel close / workspace close / the switch
tear the whole shell session tree down (broker session sweep + PDEATHSIG
backstop). No broker/shell process exists before the user flips the switch.
The non-interactive pipe runner stays the default path (and the honest
fallback when the broker binary is absent or the platform is not Linux);
tasks/tests/launch profiles stay on it so their exit codes keep driving
status. Existing contiguous pipe line storage remains separate to avoid
regressing borrowed UI/diagnostic data. macOS/Windows PTY remain gated (see
sidecar README platform gates).
