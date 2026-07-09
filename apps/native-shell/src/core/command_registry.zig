//! Authoritative, dependency-neutral command palette metadata.
//! Keep Native SDK types and model messages out of this module so both layers
//! can project the catalog without a generated source file.

pub const Availability = enum {
    available,
    limited,
    unavailable,
    hidden,

    pub fn label(value: Availability) []const u8 {
        return switch (value) {
            .available => "Available",
            .limited => "Limited",
            .unavailable => "Unavailable",
            .hidden => "Hidden",
        };
    }
};

/// Dispatch coverage is declarative: tests verify every visible command is
/// registered here, while intentionally non-dispatchable entries must carry an
/// explicit availability exemption.
pub const DispatchCoverage = enum {
    model,
    availability_exempt,
};

pub const Command = struct {
    id: []const u8,
    title: []const u8,
    hint: []const u8 = "",
    availability: Availability = .available,
    feature_id: ?[]const u8 = null,
    dispatch: DispatchCoverage = .model,
};

pub const PaletteCommand = struct {
    id: []const u8,
    title: []const u8,
    hint: []const u8,
    availability: Availability,
    availability_label: []const u8,
};

pub const catalog = [_]Command{
    .{ .id = "open_folder", .title = "Open Folder", .hint = "Cmd+O", .feature_id = "feature.workspace-manager" },
    .{ .id = "save_file", .title = "Save File", .hint = "Cmd+S", .feature_id = "feature.dirty-state" },
    .{ .id = "overwrite_file", .title = "Overwrite File Changed on Disk", .feature_id = "feature.dirty-state" },
    .{ .id = "save_all", .title = "Save All Dirty Tabs", .hint = "Cmd+Shift+S", .feature_id = "feature.dirty-state" },
    .{ .id = "create_new_file", .title = "New File", .feature_id = "feature.file-explorer" },
    .{ .id = "delete_selected_file", .title = "Delete Selected File", .feature_id = "feature.file-explorer" },
    .{ .id = "rename_selected_file", .title = "Rename Selected File", .feature_id = "feature.file-explorer" },
    .{ .id = "reveal_in_explorer", .title = "Reveal Active File in Explorer", .feature_id = "feature.file-explorer" },
    .{ .id = "quick_open", .title = "Quick Open File", .hint = "Cmd+P", .feature_id = "feature.quick-open" },
    .{ .id = "navigate_back", .title = "Navigate Back" },
    .{ .id = "navigate_forward", .title = "Navigate Forward" },
    .{ .id = "find_in_file", .title = "Find in File", .hint = "Cmd+F", .feature_id = "feature.find-replace" },
    .{ .id = "replace_once", .title = "Replace Once", .feature_id = "feature.find-replace" },
    .{ .id = "replace_all", .title = "Replace All", .feature_id = "feature.find-replace" },
    .{ .id = "copy_active_path", .title = "Copy Active Path" },
    .{ .id = "toggle_auto_save", .title = "Toggle Auto Save", .feature_id = "feature.auto-save" },
    .{ .id = "toggle_find_case", .title = "Toggle Find Case Sensitivity", .feature_id = "feature.find-replace" },
    .{ .id = "goto_line", .title = "Go to Line", .hint = "Cmd+G" },
    .{ .id = "close_active_tab", .title = "Close Active Tab", .hint = "Cmd+W", .feature_id = "feature.tabs" },
    .{ .id = "close_other_tabs", .title = "Close Other Tabs", .feature_id = "feature.tabs" },
    .{ .id = "close_all_tabs", .title = "Close All Tabs", .feature_id = "feature.tabs" },
    .{ .id = "pin_active_tab", .title = "Pin / Unpin Active Tab", .feature_id = "feature.tabs" },
    .{ .id = "toggle_focus_mode", .title = "Toggle Focus Mode" },
    .{ .id = "toggle_shortcuts_help", .title = "Keyboard Shortcuts Help", .hint = "Cmd+Shift+/", .feature_id = "feature.keybindings" },
    .{ .id = "transform_upper", .title = "Transform: Upper Case" },
    .{ .id = "transform_lower", .title = "Transform: Lower Case" },
    .{ .id = "transform_title", .title = "Transform: Title Case" },
    .{ .id = "transform_sort_lines", .title = "Transform: Sort Lines" },
    .{ .id = "transform_reverse_lines", .title = "Transform: Reverse Lines" },
    .{ .id = "collapse_blank_lines", .title = "Collapse Blank Lines" },
    .{ .id = "copy_all_tab_paths", .title = "Copy All Open Tab Paths" },
    .{ .id = "new_untitled", .title = "New Untitled File", .hint = "Cmd+N" },
    .{ .id = "delete_last_line", .title = "Delete Last Line", .hint = "Cmd+Shift+K" },
    .{ .id = "join_lines", .title = "Join Lines" },
    .{ .id = "move_line_up", .title = "Move Last Line Up" },
    .{ .id = "move_line_down", .title = "Move Last Line Down" },
    .{ .id = "undo_edit", .title = "Undo Last Edit", .hint = "Cmd+Z" },
    .{ .id = "redo_edit", .title = "Redo Last Edit", .hint = "Cmd+Shift+Z" },
    .{ .id = "revert_file", .title = "Revert File from Disk", .feature_id = "feature.dirty-state" },
    .{ .id = "restore_backup", .title = "Restore Active File from Backup", .feature_id = "feature.backups" },
    .{ .id = "copy_absolute_path", .title = "Copy Absolute Path" },
    .{ .id = "next_tab", .title = "Next Tab", .hint = "Ctrl+Tab", .feature_id = "feature.tabs" },
    .{ .id = "prev_tab", .title = "Previous Tab", .hint = "Ctrl+Shift+Tab", .feature_id = "feature.tabs" },
    .{ .id = "remove_blank_lines", .title = "Remove Blank Lines" },
    .{ .id = "insert_blank_line", .title = "Insert Blank Line at End" },
    .{ .id = "copy_filename", .title = "Copy File Name" },
    .{ .id = "show_word_count", .title = "Show Word Count" },
    .{ .id = "cycle_indent_size", .title = "Cycle Indent Size (2/4)" },
    .{ .id = "convert_tabs_to_spaces", .title = "Convert Tabs to Spaces" },
    .{ .id = "convert_spaces_to_tabs", .title = "Convert Spaces to Tabs" },
    .{ .id = "transform_sort_unique", .title = "Transform: Sort Unique Lines" },
    .{ .id = "convert_to_lf", .title = "Convert Line Endings to LF" },
    .{ .id = "convert_to_crlf", .title = "Convert Line Endings to CRLF" },
    .{ .id = "toggle_find_whole_word", .title = "Toggle Find Whole Word", .feature_id = "feature.find-replace" },
    .{ .id = "duplicate_selected_file", .title = "Duplicate Selected File", .feature_id = "feature.file-explorer" },
    .{ .id = "toggle_search_case", .title = "Toggle Search Case Sensitivity", .feature_id = "feature.workspace-search" },
    .{ .id = "toggle_search_whole_word", .title = "Toggle Search Whole Word", .feature_id = "feature.workspace-search" },
    .{ .id = "toggle_sidebar", .title = "Toggle Sidebar", .hint = "Cmd+B", .feature_id = "feature.sidebar" },
    .{ .id = "insert_timestamp", .title = "Insert Timestamp" },
    .{ .id = "toggle_trim_trailing", .title = "Toggle Trim Trailing Whitespace" },
    .{ .id = "toggle_final_newline", .title = "Toggle Insert Final Newline" },
    .{ .id = "toggle_terminal", .title = "Toggle Terminal", .hint = "Ctrl+`", .feature_id = "feature.terminal" },
    .{ .id = "run_terminal", .title = "Run Terminal Command", .feature_id = "feature.terminal" },
    .{ .id = "stop_terminal_task", .title = "Stop Terminal/Task", .feature_id = "feature.terminal" },
    .{ .id = "run_selected_task", .title = "Run Selected Workspace Task", .hint = "Cmd+Shift+B", .feature_id = "feature.task-runner" },
    .{ .id = "run_workspace_tests", .title = "Run Workspace Tests", .feature_id = "feature.test-core" },
    .{ .id = "rerun_workspace_tests", .title = "Rerun Workspace Tests", .feature_id = "feature.test-core" },
    .{ .id = "refresh_tasks", .title = "Refresh Workspace Tasks", .feature_id = "feature.task-detector" },
    .{ .id = "run_search", .title = "Search Workspace", .hint = "Cmd+Shift+F", .feature_id = "feature.workspace-search" },
    .{ .id = "preview_workspace_replace", .title = "Preview Workspace Replace", .feature_id = "feature.search-replace" },
    .{ .id = "apply_workspace_replace", .title = "Apply Workspace Replace", .feature_id = "feature.search-replace" },
    .{ .id = "refresh_git", .title = "Refresh Git Status", .feature_id = "feature.git-status" },
    .{ .id = "stage_git_entry", .title = "Git: Stage Selected File", .feature_id = "feature.git-stage-commit" },
    .{ .id = "unstage_git_entry", .title = "Git: Unstage Selected File", .feature_id = "feature.git-stage-commit" },
    .{ .id = "restore_git_entry", .title = "Git: Restore Selected File", .feature_id = "feature.git-stage-commit" },
    .{ .id = "stage_all", .title = "Git: Stage All", .feature_id = "feature.git-stage-commit" },
    .{ .id = "unstage_all", .title = "Git: Unstage All", .feature_id = "feature.git-stage-commit" },
    .{ .id = "discard_changes", .title = "Git: Discard Working Tree", .feature_id = "feature.git-stage-commit" },
    .{ .id = "commit_changes", .title = "Git: Commit", .feature_id = "feature.git-stage-commit" },
    .{ .id = "trim_blank_lines", .title = "Trim Leading/Trailing Blank Lines" },
    .{ .id = "refresh_explorer", .title = "Refresh Explorer", .feature_id = "feature.file-explorer" },
    .{ .id = "refresh_disk_sync", .title = "Refresh Files from Disk", .feature_id = "feature.file-watchers" },
    .{ .id = "close_saved_tabs", .title = "Close Saved Tabs", .feature_id = "feature.tabs" },
    .{ .id = "compare_with_saved", .title = "Compare with Saved", .feature_id = "feature.compare-files" },
    .{ .id = "copy_git_branch", .title = "Copy Git Branch", .feature_id = "feature.git-branches" },
    .{ .id = "clear_recent_projects", .title = "Clear Recent Projects", .feature_id = "feature.recent-projects" },
    .{ .id = "insert_uuid", .title = "Insert UUID" },
    .{ .id = "format_document", .title = "Format Document", .hint = "Shift+Alt+F", .feature_id = "feature.formatting" },
    .{ .id = "hard_wrap", .title = "Hard Wrap at 80" },
    .{ .id = "copy_document", .title = "Copy Document" },
    .{ .id = "go_to_symbol", .title = "Go to Symbol in File", .hint = "Cmd+Shift+O", .feature_id = "feature.symbol-search" },
    .{ .id = "go_to_definition", .title = "Go to Definition", .hint = "Cmd+Shift+D", .feature_id = "feature.go-to-definition" },
    .{ .id = "open_outline", .title = "Open Outline", .feature_id = "feature.outline" },
    .{ .id = "toggle_bottom_panel", .title = "Toggle Bottom Panel", .hint = "Cmd+J", .feature_id = "feature.panel" },
    .{ .id = "clear_output", .title = "Clear Output", .feature_id = "feature.output-panel" },
    .{ .id = "create_folder", .title = "New Folder", .feature_id = "feature.file-explorer" },
    .{ .id = "show_file_size", .title = "Show File Size", .feature_id = "feature.file-explorer" },
    .{ .id = "toggle_word_wrap", .title = "Toggle Word Wrap", .hint = "Alt+Z" },
    .{ .id = "check_for_updates", .title = "Check for Updates (Limited)", .availability = .limited },
    .{ .id = "toggle_notifications_panel", .title = "Toggle Notifications", .feature_id = "feature.notifications" },
    .{ .id = "minimize_window", .title = "Minimize Window" },
    .{ .id = "close_window", .title = "Close Window" },
    .{ .id = "reopen_last_workspace", .title = "Reopen Last Workspace", .feature_id = "feature.recent-projects" },
    .{ .id = "clear_find", .title = "Clear Find", .feature_id = "feature.find-replace" },
    .{ .id = "duplicate_line", .title = "Duplicate Last Line" },
    .{ .id = "toggle_line_comment", .title = "Toggle Line Comment", .hint = "Cmd+/" },
    .{ .id = "indent_document", .title = "Indent Document" },
    .{ .id = "outdent_document", .title = "Outdent Document" },
    .{ .id = "reopen_closed_tab", .title = "Reopen Closed Tab", .hint = "Cmd+Shift+T", .feature_id = "feature.tabs" },
    .{ .id = "scan_problems", .title = "Scan TODO/FIXME Problems", .feature_id = "feature.problems" },
    .{ .id = "parse_terminal_diagnostics", .title = "Parse Terminal Diagnostics", .feature_id = "feature.problem-matchers" },
    .{ .id = "toggle_agent", .title = "Toggle Agent Panel", .hint = "Cmd+Shift+A", .feature_id = "feature.agent-composer" },
    .{ .id = "open_plugins", .title = "Open Plugin Registry (Limited)", .availability = .limited, .feature_id = "feature.plugin-marketplace-ui" },
    .{ .id = "open_settings", .title = "Open Settings", .hint = "Cmd+,", .feature_id = "feature.settings" },
    .{ .id = "run_perf", .title = "Refresh Performance Metrics", .feature_id = "feature.performance-hud" },
    .{ .id = "open_feature_matrix", .title = "Open Feature Toggle Matrix", .feature_id = "feature.feature-toggle-matrix" },
    .{ .id = "open_process_governor", .title = "Open Process Governor", .feature_id = "feature.process-governor-ui" },
    .{ .id = "kill_all_workspace_processes", .title = "Kill All Workspace Processes", .feature_id = "feature.kill-all-workspace-processes" },
    .{ .id = "instant_safe_mode", .title = "Instant Safe Mode", .feature_id = "feature.instant-safe-mode" },
    .{ .id = "switch_theme", .title = "Switch Theme", .feature_id = "feature.themes" },
    .{ .id = "new_agent_task", .title = "New Agent Task", .availability = .hidden, .feature_id = "feature.agent-task-list", .dispatch = .availability_exempt },
    .{ .id = "go_launch", .title = "Back to Launch Screen", .feature_id = "feature.welcome-empty-state" },
};

pub const builtin = catalog;

pub const palette_count = blk: {
    var count: usize = 0;
    for (catalog) |command| {
        if (command.availability != .hidden) count += 1;
    }
    break :blk count;
};

pub const palette = blk: {
    var projected: [palette_count]PaletteCommand = undefined;
    var index: usize = 0;
    for (catalog) |command| {
        if (command.availability == .hidden) continue;
        projected[index] = .{
            .id = command.id,
            .title = command.title,
            .hint = command.hint,
            .availability = command.availability,
            .availability_label = command.availability.label(),
        };
        index += 1;
    }
    break :blk projected;
};

comptime {
    @setEvalBranchQuota(20_000);
    for (catalog, 0..) |command, index| {
        if (command.id.len == 0) @compileError("command IDs must not be empty");
        for (catalog[index + 1 ..]) |other| {
            if (equal(command.id, other.id)) @compileError("duplicate command ID");
        }
        if (command.dispatch == .availability_exempt and
            command.availability != .hidden and
            command.availability != .unavailable)
        {
            @compileError("dispatch exemptions require hidden or unavailable commands");
        }
    }
}

fn equal(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left != right) return false;
    }
    return true;
}
