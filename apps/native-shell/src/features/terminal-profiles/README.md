# Terminal Profiles

- **id:** `feature.terminal-profiles`
- **mode:** `core`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `4`
- **maxProcesses:** `0`
- **activation:** `onTerminalOpen`

Loads up to 12 command-only profiles from `.velocity/launch.json` on workspace
open or refresh. Schema version `1` accepts `profiles[]` with bounded `name`,
`command`, relative `cwd`, and up to 12 environment entries. DAP/debug keys,
absolute or traversing working directories, and configuration variable
placeholders are rejected.

Profiles run through the same pipe-terminal effect, Stop action, and one-process
Governor budget as terminal commands, tasks, and tests. This is a run-profile
format, not a debugger configuration format.
