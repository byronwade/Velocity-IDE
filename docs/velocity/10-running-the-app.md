# Running Velocity

## Install

Use Node.js 22 and run installation only from the repository root:

```bash
npm install
```

The root postinstall runs `npm ci --prefix .tools`, installing exactly Native
SDK CLI 0.4.0 from the tracked `.tools/package-lock.json`. Do not install a
second project CLI dependency.

### Linux system deps (for `npm run build` / `npm run dev`)

```bash
sudo apt-get install -y libgtk-4-dev libwebkitgtk-6.0-dev
```

Native commands may download the CLI's official pinned Zig toolchain when it is
missing.

## Dev

```bash
npm run check    # feature drift + 252 tests + strict .native/app validation
npm test         # 252 headless UI + unit/model tests
npm run build    # ReleaseFast -> apps/native-shell/zig-out/bin/velocity-ide
npm run dev      # Debug build + run with markup hot reload
npm run doctor
```

## Smoke suites

```bash
npm run smoke
npm run smoke:perf
npm run smoke:task
npm run smoke:test
npm run smoke:launch
npm run smoke:explorer
npm run smoke:review-snippet
npm run smoke:terminal
npm run smoke:diagnostics
```

## Troubleshooting

| Issue | Fix |
|---|---|
| Zig missing on PATH | Run `npm run doctor`; the CLI manages its compatible toolchain |
| Link fails: `libgtk4` / `webkitgtk-6.0` | Install Linux deps above |
| Font/tofu errors in check | Avoid special Unicode in markup text; use ASCII or `<icon>` |
| `on-press` payload errors | Use `{binding}` payloads, not string literals |
| Headless CI | Use `npm test`; smoke scripts require Xvfb |

See `native-sdk-blockers.md` for the cloud-agent run log.
