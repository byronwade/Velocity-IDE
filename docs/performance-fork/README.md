# Performance Fork Documentation

1. [Architecture audit](./architecture-audit.md)
2. [Product profile](./product-profile.md)
3. [Built-in extension audit](./builtin-extension-audit.md)
4. [Terminal performance](./terminal-performance.md)
5. [Minimal UI](./minimal-ui.md)
6. [Build system options](./build-system-options.md)
7. [Change checklist](./change-checklist.md)
8. [Roadmap](./roadmap.md)

## Quick start

```bash
# Core Mode (default)
./scripts/code.sh

# Developer Mode
./scripts/code.sh --perf-fork-mode=developer

# Compat Mode
./scripts/code.sh --perf-fork-mode=compat

# Static perf harness
npm run perf-fork
```
