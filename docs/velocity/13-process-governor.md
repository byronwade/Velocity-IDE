# Process Governor

## Rule
**No feature may spawn a child process directly.** All launches go through `apps/native-shell/src/processes/process_governor.zig`.

## Tracked fields
id, os_pid, parent_feature, workspace_id, command, cwd, start/last activity, memory/CPU estimates, kill/idle/trust policies, terminal/LSP/task/debug ownership, alive/leaked flags.

## Cleanup
- Feature disable → kill feature-owned
- Workspace close → kill workspace-owned
- Terminal close → kill tree unless detached
- Task end/cancel → kill task tree
- Debug session end → kill adapter tree
- LSP idle / no relevant files → suspend or kill
- Reap orphans; surface leaks in Performance HUD

## Limits
See `process_limits.zig` (workspace/LSP/terminal/plugin caps).

## Status
Scaffold records spawns without OS exec yet.
