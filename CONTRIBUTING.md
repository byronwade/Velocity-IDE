# Contributing to Velocity

Open an issue before large changes. Keep changes focused, preserve bounded
resource behavior, and do not add Microsoft branding, marketplace services, or
upstream VS Code source.

## Development

Use Node.js 22 and run commands from the repository root:

```bash
npm install
npm run check
npm run build
```

`npm run check` verifies feature metadata, runs native tests, and performs the
strict app check. Run the relevant `npm run smoke:<name>` suite for UI or
process changes. Update
documentation and tests with behavior changes. Pull requests should explain
scope, validation, user-visible impact, and known limitations.

By participating, you agree to follow [the Code of Conduct](CODE_OF_CONDUCT.md).
Report security issues privately as described in [SECURITY.md](SECURITY.md).
