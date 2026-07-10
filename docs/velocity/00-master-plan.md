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
- Real AI network calls, plugin downloads, or shell execution in the scaffold
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
| M0 | Docs + rules + Native SDK scaffold (this pass) |
| M1 | Running mock IDE shell (launch + IDE chrome) |
| M2 | Workspace core: open folder, file tree, save |
| M3 | Monaco editor island after first paint |
| M4 | Native terminal prototype |
| M5 | LSP broker + one language server |
| M6 | Plugin runtime + permissions enforcement |
| M7 | Registry client (signed, allowlisted) |
| M8 | Optional legacy VSIX bridge (sandboxed) |

## Risk register

| Risk | Mitigation |
|---|---|
| Native SDK pre-1.0 / platform gaps | Document blockers; preserve a Linux software-renderer path |
| Zig/toolchain friction | CLI downloads pinned Zig; document setup |
| Editor quality gap vs Monaco | Editor island WebView, not shell WebView |
| Plugin ecosystem cold start | Trusted core plugins + clear author SDK |
| Legal/brand confusion | Codename rename-ready; no third-party assets |

## First 30-day roadmap

1. Week 1: Running shell + design tokens + docs (done in scaffold)
2. Week 2: Real folder open + document model
3. Week 3: Monaco island behind first paint
4. Week 4: Terminal PTY prototype + perf marks
