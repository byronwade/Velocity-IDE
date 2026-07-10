# Snippets

- **id:** `feature.snippets`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onFileOpen`

## Rules

- Loads bounded schema version 1 from `.velocity/snippets.json`.
- Optionally loads the file named by `VELOCITY_USER_CONFIG`; workspace prefixes override user prefixes.
- Rejects oversized entries, tabstops, placeholders, `$()` substitutions, and backtick substitutions.
- `Append Snippet` appends the literal body because the native textarea has no caret API. It uses normal undo, dirty-state, auto-save, and safe-save behavior.
- Limits: 16 KiB source, 32 snippets, 48-byte prefixes, 1 KiB bodies, and 160-byte descriptions.
