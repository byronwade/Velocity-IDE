# 04 · Workbench UX and design system

Goal: the cleanest, most visually cohesive desktop app on the market —
minimalistic but feature rich. Warm neutral foundation, hairline structure,
icon-first chrome, real modal surfaces, one size register per row.

Recently landed on the redesign branch (keep polishing, don't regress):
warm stone/sand tokens for dark+light, softened radii, icon-only activity
rail, vector icons across the chrome, breadcrumb row + flush editor, dense
explorer tree with icon chevrons, native dialog surfaces for every overlay,
humanized perf HUD, centered settings column, CI screenshot tour for visual
review.

## Todo

- [x] P0 Warm token system (dark + light) with single amber signal — landed.
- [x] P0 Icon-only activity rail + vector icons throughout — landed.
- [x] P0 Native `dialog` for palette/quick-open/notifications/etc. — landed.
- [x] P0 Editor chrome: nav in tab strip, breadcrumb line, flush editor —
      landed.
- [ ] P0 [TS] Real tab affordances: selected tab visually attached to the
      editor (toggle-button tab strip per SDK `tabs` element), close glyph on
      the active tab, dirty dot indicator per tab.
- [ ] P1 [TS] Hover/selection states audit against the amber focus token:
      list rows, tree rows, tabs, palette items — one consistent selection
      treatment everywhere (screenshot-tour diffs as evidence).
- [ ] P1 [TS] Toasts as floating bottom-right surfaces instead of full-width
      strips above the status bar.
- [ ] P1 [TS] Status bar segments become interactive (branch → SCM panel,
      language → symbol palette, problems count → problems panel).
- [ ] P1 [TS] Empty states: explorer with no folder, search before first
      query, agent panel with no tasks — one calm, consistent pattern
      (muted icon + one sentence + one action).
- [ ] P1 [DIFF] Split editor groups (SDK `split` element) — two panes with
      draggable divider; tab strips per group.
- [ ] P1 [TS] Keyboard focus ring pass: every interactive element reachable
      and visibly focused; run `expectA11yAuditSweepClean` in tests.
- [ ] P2 [TS] Editor as real component (not textarea): line numbers gutter,
      selection highlight, current-line tint — arrives with the rope engine
      and the SDK editor island (docs/velocity bridge notes).
- [ ] P2 [DIFF] Theme gallery: ship 2-3 hand-tuned themes (warm dark, warm
      light, high-contrast) with the token system as the only theming API —
      curated over configurable.
- [ ] P2 [TS] Window chrome niceties: remember window frame per workspace
      (restore_state), native context menus on tree/tabs (SDK context-menu).
