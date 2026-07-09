# Native SDK Blockers Log

## Environment notes (cloud agent, 2026-07-09)

- Host: Linux x86_64
- `@native-sdk/cli` **0.4.0** installed under `.tools/` (`npm install --prefix .tools @native-sdk/cli`)
- Zig **0.16.0** auto-downloaded by CLI to `~/.native/toolchains/zig-0.16.0`
- Display: `DISPLAY=:1` available in this environment

## Commands status

| Command | Result |
|---|---|
| `native check` | **Pass** (markup + app.zon; existing unbound-model warnings remain) |
| `native test` | **Pass** (170/170 tests after integration-boundary scaffolds) |
| `native build` | **Pass** after installing `libgtk-4-dev` + `libwebkitgtk-6.0-dev` → `zig-out/bin/velocity-ide` |
| `native doctor` | Zig not on PATH (CLI-managed OK); WebKit/GTK were missing until apt install |
| Interactive `native dev` / binary window | Attempted with short timeout; see run log below |

## Fixed during scaffold

1. Bundled-font tofu guard rejected `⌘` and other symbols — replaced with ASCII (`Cmd+K`, `/` separators).
2. Markup `on-press` payloads must be `{bindings}`, not string/enum literals — exposed model constants (`activity_*`, `project_acme`, …).
3. Zig 0.16 rejects `.close_tab => |_| {}` — use `.close_tab => {}`.
4. Linux ReleaseFast link requires GTK4 + WebKitGTK 6.0 even for canvas-only shell (SDK host links them).

## Remaining / known

- Linux packaging still pulls WebKitGTK even when the shell is GPU canvas only (no editor WebView yet).
- `zig` is not on PATH unless you add `~/.native/toolchains/zig-0.16.0` or rely on `native * --yes`.
- Do not claim real startup/memory benchmarks yet — perf HUD values are **mock**.
- Empty `src/ui` / `src/workspace` dirs were removed (no theater). Terminal panel markup lives in `app.native`; `terminal/terminal_view.native` is a future extract stub.
- The textarea has no stable gutter/decoration API or caret/scroll
  synchronization contract. Line numbers remain a separate bounded peek, not a
  real editor gutter.
- A recurring Effects timer is not wired. It requires an app-lifetime timer
  ownership contract with cancellation on window/app teardown and no callbacks
  into deinitialized model state. Interaction polling and manual disk refresh
  remain the honest fallback.

## Daily-driver integration boundaries

These are **scaffolds**, not working integrations:

| System | Scaffold present | Runtime status | Exact unblock criteria |
|---|---|---|---|
| Editor island | Typed textarea/Monaco/native backend, state, command, selection, revision, and event protocol | Textarea remains in use; Monaco/WebView blocked by SDK; native editor is research only | Stable embedded WebView lifecycle and bidirectional messaging; documented focus, keyboard, IME, and accessibility forwarding. A stable textarea gutter/decoration plus caret/scroll API, or supported custom editor surface, is separately required for real gutters. |
| LSP broker | Bounded Content-Length framing, request IDs, sessions, pending requests, and diagnostic snapshots | Transport unavailable; no language server is spawned or claimed | Supported long-lived child process with stdin/stdout streams; incremental reads; write backpressure; cancellation and exit events; process-tree ownership integrated with Process Governor and Effects. |
| Terminal PTY | Bounded output ring, input queue, resize commands, and lifecycle events | PTY transport unavailable; existing non-interactive pipe command runner still works | Cross-platform PTY spawn API; streaming stdin/stdout; resize events; process-tree close/cancellation integrated with Process Governor and Effects. |

The protocol modules return or expose `unavailable` for blocked transports. Unit
tests validate only in-memory boundaries and must not be read as end-to-end SDK
coverage.

## Install deps (Linux)

```bash
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev
```

## Feature parity pass (2026-07-09)

- `native check` / `native test` / `native build` passed after feature registry + Process Governor scaffold; latest boundary work revalidated check + 170 tests (build not rerun).
- Zig reserved word: enum member cannot be named `suspend` — use `suspend_idle`.
