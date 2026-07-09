# Native SDK Blockers Log

## Environment notes (cloud agent, 2026-07-09)

- Host: Linux x86_64
- `@native-sdk/cli` **0.4.0** installed under `.tools/` (`npm install --prefix .tools @native-sdk/cli`)
- Zig **0.16.0** auto-downloaded by CLI to `~/.native/toolchains/zig-0.16.0`
- Display: `DISPLAY=:1` available in this environment

## Commands status

| Command | Result |
|---|---|
| `native check` | **Pass** (markup + app.zon) |
| `native test` | **Pass** (7/7 tests) |
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

## Install deps (Linux)

```bash
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev
```
