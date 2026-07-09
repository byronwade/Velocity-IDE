//! Legacy feature-metadata command subset.
//! Runtime palette commands remain in model/app_model.zig until they can be
//! migrated together with update dispatch and shortcut registration.
pub const Command = struct {
    id: []const u8,
    title: []const u8,
    feature_id: []const u8,
    hint: []const u8 = "",
};

pub const builtin = [_]Command{
    .{ .id = "open_folder", .title = "Open Folder", .feature_id = "feature.workspace-manager", .hint = "Cmd+O" },
    .{ .id = "toggle_terminal", .title = "Toggle Terminal", .feature_id = "feature.terminal", .hint = "Ctrl+`" },
    .{ .id = "toggle_agent", .title = "Toggle Agent Panel", .feature_id = "feature.agent-composer", .hint = "Cmd+Shift+A" },
    .{ .id = "open_plugins", .title = "Open Plugin Registry", .feature_id = "feature.plugin-marketplace-ui" },
    .{ .id = "open_settings", .title = "Open Settings", .feature_id = "feature.settings", .hint = "Cmd+," },
    .{ .id = "run_perf", .title = "Run Performance Check", .feature_id = "feature.performance-hud" },
    .{ .id = "open_feature_matrix", .title = "Open Feature Toggle Matrix", .feature_id = "feature.feature-toggle-matrix" },
    .{ .id = "open_process_governor", .title = "Open Process Governor", .feature_id = "feature.process-governor-ui" },
    .{ .id = "kill_all_workspace_processes", .title = "Kill All Workspace Processes", .feature_id = "feature.kill-all-workspace-processes" },
    .{ .id = "instant_safe_mode", .title = "Instant Safe Mode", .feature_id = "feature.instant-safe-mode" },
    .{ .id = "switch_theme", .title = "Switch Theme", .feature_id = "feature.themes" },
    .{ .id = "new_agent_task", .title = "New Agent Task", .feature_id = "feature.agent-task-list" },
    .{ .id = "go_launch", .title = "Back to Launch Screen", .feature_id = "feature.welcome-empty-state" },
};
