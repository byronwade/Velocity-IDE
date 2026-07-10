# Design System

## Principles (inspired, not copied)

- Dark-first, high contrast, hairline borders
- Warm, clean neutral foundation (stone/sand undertone, never cold zinc)
- Compact density, keyboard-first
- Command palette centrality
- Agent task cards with clear status
- Monochrome primary; a single restrained amber signal for focus/selection
- Softly rounded, calm chrome — modern without going bubbly
- No cartoon noise, no brand asset copying

## Do-not-copy rule

Do **not** ship Cursor/Vercel logos, names, exact layouts, proprietary assets, website copy, screenshots, icons, CSS, or trade dress. Codename “Velocity” is temporary and rename-ready.

## Tokens

Implemented in `apps/native-shell/src/theme/tokens.zig` mapping to Native SDK `ColorTokens` / `DesignTokens`. The neutral ramp carries a warm (stone/sand) undertone rather than cold zinc so surfaces read calm and warm at every elevation.

| Token intent | Dark value | Light value |
|---|---|---|
| background (ink / paper) | #0D0C0B | #FAF9F6 |
| surface | #14120F | #FFFFFD |
| surface subtle | #1C1917 | #F4F2ED |
| text primary | #F7F4EF | #1C1916 |
| text muted | #978F85 | #7A7268 |
| border | warm white @ ~8% | #E8E3DA |
| accent (mono primary) | #F6F3EE | #1C1916 |
| focus / selection (amber) | #DBAA6C | #C69254 |
| info / blue | #7EA4F4 | #2C62D6 |
| success / warning / danger | #4EBE82 / #E09E52 / #E95C4E | #1C9462 / #BE7A26 / #CE4438 |

Radii soften to `sm 4 · md 7 · lg 11 · xl 15` for a modern, calm chrome that stays dense.

## Iconography

Built-in Native SDK stroke icons only (`<icon name>` / `icon=` attributes) — a
closed, compile-checked set, tinted through the color tokens. The activity
rail is icon-only with full accessible labels; icon-only controls always
carry a `label`. Explorer folder chevrons bind icon names
(`chevron-right` / `chevron-down`) from the projection. No emoji, no
third-party icon fonts, no copied brand glyphs.

## Typography

System stacks only — no vendored proprietary font files. Optional: SDK-bundled Geist faces if used via official registration APIs.

## Motion

Prefer reduced motion when OS requests it. Palette open must not delay input.
