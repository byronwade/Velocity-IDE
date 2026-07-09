# Design System

## Principles (inspired, not copied)

- Dark-first, high contrast, hairline borders
- Compact density, keyboard-first
- Command palette centrality
- Agent task cards with clear status
- Monochrome foundation; restrained accent
- No cartoon noise, no brand asset copying

## Do-not-copy rule

Do **not** ship Cursor/Vercel logos, names, exact layouts, proprietary assets, website copy, screenshots, icons, CSS, or trade dress. Codename “Velocity” is temporary and rename-ready.

## Tokens

Implemented in `apps/native-shell/src/theme/tokens.zig` mapping to Native SDK `ColorTokens` / `DesignTokens`.

| Token intent | Dark value |
|---|---|
| canvas | #050505 |
| surface | #0A0A0A |
| elevated | #111111 |
| overlay | #161616 |
| text primary | #F5F5F5 |
| text muted | #737373 |
| border | white @ 8% |
| accent | #F5F5F5 (mono) |
| info/blue | #3B82F6 |
| success / warning / danger | #22C55E / #F59E0B / #EF4444 |

## Typography

System stacks only — no vendored proprietary font files. Optional: SDK-bundled Geist faces if used via official registration APIs.

## Motion

Prefer reduced motion when OS requests it. Palette open must not delay input.
