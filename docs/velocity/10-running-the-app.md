# Running Velocity

## Install

```bash
# CLI (global or local)
npm install -g @native-sdk/cli
# or from repo root:
npm install --prefix .tools @native-sdk/cli
export PATH="$PWD/.tools/node_modules/.bin:$PATH"

native version   # expect 0.4.x+
```

### Linux system deps (for `native build` / `native dev`)

```bash
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev
```

Zig is downloaded automatically by the CLI (`native * --yes`) into `~/.native/toolchains/`.

## Dev

```bash
cd apps/native-shell
npm run check    # validate .native markup + app.zon
npm run test     # headless UI + unit/model tests
npm run build    # ReleaseFast → zig-out/bin/velocity-ide
npm run dev      # Debug build + run with markup hot reload
npm run perf-smoke
npm run task-smoke
npm run test-smoke # deterministic workspace test pass + controlled failure
```

Or:

```bash
native check
native test --yes
native build --yes
native dev --yes
```

## Troubleshooting

| Issue | Fix |
|---|---|
| Zig missing on PATH | Use `native … --yes` (CLI-managed toolchain) |
| Link fails: `libgtk4` / `webkitgtk-6.0` | Install Linux deps above |
| Font/tofu errors in check | Avoid special Unicode in markup text; use ASCII or `<icon>` |
| `on-press` payload errors | Use `{binding}` payloads, not string literals |
| Headless CI | Prefer `native test`; interactive window needs a display |

See `native-sdk-blockers.md` for the cloud-agent run log.
