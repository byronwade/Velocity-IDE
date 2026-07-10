# Native SDK Blockers Log

## Environment notes (Linux validation, 2026-07-09)

- Host: Linux x86_64
- `@native-sdk/cli` **0.4.0** installed under `.tools/` by root `npm install`
- Zig **0.16.0** auto-downloaded by CLI to `~/.native/toolchains/zig-0.16.0`
- Display: `DISPLAY=:1` available in this environment

## Commands status

| Command | Result |
|---|---|
| `npm run check` | **Pass**: generated feature check, 252/252 native tests, strict markup/app validation |
| `npm test` | **Pass**: 252/252 native tests |
| `npm run build` | **Pass on Linux** after installing GTK4 + WebKitGTK 6.0 development packages |
| `npm run doctor` | Zig may be absent from PATH; the pinned CLI manages its compatible toolchain |

The earlier 170/170 count in this log was a historical scaffold measurement
and is obsolete. The current recorded native test count is 252.

## Fixed during scaffold

1. Bundled-font tofu guard rejected `⌘` and other symbols — replaced with ASCII (`Cmd+K`, `/` separators).
2. Markup `on-press` payloads must be `{bindings}`, not string/enum literals — exposed model constants (`activity_*`, `project_acme`, …).
3. Zig 0.16 rejects `.close_tab => |_| {}` — use `.close_tab => {}`.
4. Linux ReleaseFast link requires GTK4 + WebKitGTK 6.0 even for canvas-only shell (SDK host links them).

## Remaining / known

- Linux packaging still pulls WebKitGTK even when the shell is GPU canvas only (no editor WebView yet).
- `zig` is not on PATH unless you add `~/.native/toolchains/zig-0.16.0` or rely on `native * --yes`.
- Performance values are reported only when measured by the runtime; unsupported
  RSS/process/startup values remain explicitly `n/a`. Budgets are not benchmark
  claims.
- The textarea has no stable gutter/decoration API or caret/scroll
  synchronization contract. Line numbers remain a separate bounded peek, not a
  real editor gutter.
- Recurring disk polling is wired in `src/model/app_model.zig` as one keyed
  Effects timer. It is cancelled outside a disk-backed workspace, re-armed
  after each accepted tick, and marks polling unavailable without a re-arm
  storm if the runtime rejects the timer. Manual refresh remains available.

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

## Historical feature parity pass (2026-07-09)

- At that point, check/test/build passed after the initial registry and Process
  Governor scaffold. Its 170-test note is retained only as history and is
  superseded by the 252-test result above.
- Zig reserved word: enum member cannot be named `suspend` — use `suspend_idle`.
