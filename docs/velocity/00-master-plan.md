# Velocity — Master Plan

## Product vision

**Velocity** is a native, minimal, agent-aware IDE. It is not a VS Code skin.
Startup and memory goals remain budgets until repeatable release measurements
demonstrate them. VS Code is an external behavioral reference at
https://github.com/microsoft/vscode.

## What we are building

- Native app shell (Vercel Labs Native SDK: Zig + `.native` markup)
- Sub-one-second perceived startup, very low idle memory
- Command-first dark UI with an agent/composer surface
- Own plugin system + curated registry
- LSP via external broker processes
- Optional VS Code extension compatibility later (legacy mode only)

## What we are not building (now)

- Rewriting the Electron workbench
- Shipping Microsoft marketplace / Copilot / telemetry by default
- Full Monaco in v0 (placeholder → island later)
- Real AI network calls or plugin downloads in the current MVP
- Copying Cursor/Vercel branding or assets

## Why not a VS Code skin

VS Code’s workbench is deeply coupled: contribution registration, extension host, Electron packaging, and decades of feature surface. Melting it into a blade is valuable research; shipping Velocity requires a clean native shell with explicit state and performance budgets.

## Role of the external VS Code baseline

1. Research editor, LSP, terminal, and extension behaviors
2. Define reproducible comparison scenarios against published VS Code builds
3. Inform optional legacy VSIX experiments without importing upstream source

## High-level milestones

| M | Outcome |
|---|---|
| M0 | Complete: standalone docs, rules, and Native SDK foundation |
| M1 | Complete: running native shell |
| M2 | MVP complete: bounded workspace editing, recovery, and pipe commands |
| M3 | Blocked: operational rich editor island after first paint |
| M4 | Blocked: native terminal PTY transport |
| M5 | Blocked: LSP transport + one language server |
| M6 | Not started: plugin runtime + permissions enforcement |
| M7 | Not started: signed, allowlisted registry client |
| M8 | Deferred: optional sandboxed legacy VSIX bridge |

## Risk register

| Risk | Mitigation |
|---|---|
| Native SDK pre-1.0 / platform gaps | Document blockers; preserve a Linux software-renderer path |
| Zig/toolchain friction | CLI downloads pinned Zig; document setup |
| Editor quality gap vs Monaco | Editor island WebView, not shell WebView |
| Plugin ecosystem cold start | Trusted core plugins + clear author SDK |
| Legal/brand confusion | Codename rename-ready; no third-party assets |

## Original 30-day outline (historical)

1. Week 1: Running shell + design tokens + docs — complete
2. Week 2: Folder open + document model — bounded MVP complete
3. Week 3: Monaco island behind first paint — not operational
4. Week 4: Terminal PTY prototype + perf marks — measured-or-unavailable perf
   exists; PTY transport remains unavailable
