# Problem Matchers

- **id:** `feature.problem-matchers`
- **mode:** `dev`
- **status:** `working`
- **implementation:** `native`
- **startupAllowed:** `False`
- **memoryBudgetMB:** `8`
- **maxProcesses:** `0`
- **activation:** `onTaskRun`, `onCommand:problem-matchers.run`

## Rules

- Lazy: activates only after a terminal command exits or via **Parse Output**.
- Parses bounded terminal output into clickable Problems without child processes.
- Supports TypeScript `path(line,col)`, Zig/GCC/Clang `path:line:col`, ANSI stripping,
  severity/code extraction, deduplication, and a 64-diagnostic cap.
- The terminal process itself remains governed by Process Governor.
