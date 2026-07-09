# Performance Fork Change Checklist

Every removal/gating change must satisfy:

## Build / boot

- [ ] TypeScript compiles (watch task / `compile-check-ts-native` as available)
- [ ] App boots in Core Mode
- [ ] App boots in Developer Mode (`--perf-fork-mode=developer`)
- [ ] App boots in Compat Mode (`--perf-fork-mode=compat`) when touching compat packs

## Basic editing

- [ ] Open a folder
- [ ] Open / edit / save a file
- [ ] Command palette opens
- [ ] Terminal opens
- [ ] Basic search returns results

## Extensions (if host enabled)

- [ ] Extension scanner runs
- [ ] One test extension loads or marketplace install path still works in Developer mode
- [ ] Activation budget does not block first paint

## Measurement

- [ ] `npm run perf-fork` runs
- [ ] `.perf-fork/latest.json` updated
- [ ] Note regressions in PR description

## Docs

- [ ] Update `architecture-audit.md` if startup graph changed
- [ ] Update `builtin-extension-audit.md` if extension diet changed
- [ ] Update `product-profile.md` if mode semantics changed

## Safety

- [ ] No blind folder deletes without import gating first
- [ ] Fallback path documented (compat mode / feature enable flags)
- [ ] Accessibility core support preserved
- [ ] Monaco / folder open / settings / keybindings / terminal / search intact
