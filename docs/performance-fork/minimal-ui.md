# Minimal UI — Focus Core

## Direction

Calm, command-driven, distraction-free. Brand the product as a performance IDE through absence of noise, not ornament.

## Principles

- No welcome / walkthrough / survey surfaces in Core
- Command palette first
- Optional sidebar / panel; activity bar hidden by default in Core
- Quiet notifications; reduced badges
- One calm default theme (Default Light Modern for now)
- No layout shifts from late-loading contrib views
- Keep accessibility support; skip decorative accessibility signals unless enabled

## Defaults (Core)

| Setting | Value |
|---|---|
| `workbench.startupEditor` | `none` |
| `workbench.activityBar.location` | `hidden` |
| `window.commandCenter` | `false` |
| `chat.commandCenter.enabled` | `false` |
| `editor.minimap.enabled` | `false` |
| `editor.stickyScroll.enabled` | `false` |
| `breadcrumbs.enabled` | `false` |
| `explorer.decorations.badges` | `false` |
| `workbench.reduceMotion` | `on` |
| `workbench.colorTheme` | `Default Light Modern` |

Registered in `performanceFork.contribution.ts` via `registerDefaultConfigurations`.

## Layout: Focus Core

First-run mental model:

1. Editor dominates
2. Explorer available via command / keybinding
3. Terminal via command / keybinding
4. Status bar minimal
5. No chat/account/remote badges

## Keybindings (command-first)

Stock VS Code keybindings remain. Emphasize in docs:

- `Ctrl/Cmd+Shift+P` — command palette
- `Ctrl/Cmd+P` — quick open
- `Ctrl/Cmd+\`` — terminal
- `Ctrl/Cmd+B` — toggle sidebar
- `Ctrl/Cmd+J` — toggle panel

## Motion

Prefer reduced motion in Core (`workbench.reduceMotion: on`). Any future motion should be limited to intentional focus transitions (2–3 max), never decorative.

## Follow-ups

- Dedicated Focus Core color theme token set (non-purple, non-cream-serif cliché)
- Status bar contribution allowlist
- Zen-like first-run layout flag persisted per profile
