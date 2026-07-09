//! Authoritative Native SDK-compatible shortcut records.
//! This module intentionally contains no Native SDK imports; main.zig projects
//! these records into the SDK's Shortcut type.

pub const Target = enum {
    palette,
    shell,
};

pub const Modifiers = struct {
    primary: bool = false,
    control: bool = false,
    shift: bool = false,
    option: bool = false,
};

pub const Binding = struct {
    /// ID delivered by the Native SDK.
    shortcut_id: []const u8,
    /// Canonical palette/dispatch ID. This differs only for intentional aliases.
    canonical_command_id: []const u8,
    key: []const u8,
    modifiers: Modifiers = .{},
    target: Target = .palette,
    hint: []const u8,
    help_label: []const u8 = "",
    show_in_help: bool = false,
};

pub const defaults = [_]Binding{
    .{ .shortcut_id = "command_palette", .canonical_command_id = "command_palette", .key = "k", .modifiers = .{ .primary = true }, .target = .shell, .hint = "Cmd+K", .help_label = "Command Palette", .show_in_help = true },
    .{ .shortcut_id = "quick_open", .canonical_command_id = "quick_open", .key = "p", .modifiers = .{ .primary = true }, .hint = "Cmd+P", .help_label = "Quick Open", .show_in_help = true },
    .{ .shortcut_id = "find_in_file", .canonical_command_id = "find_in_file", .key = "f", .modifiers = .{ .primary = true }, .hint = "Cmd+F", .help_label = "Find in File", .show_in_help = true },
    .{ .shortcut_id = "goto_line", .canonical_command_id = "goto_line", .key = "g", .modifiers = .{ .primary = true }, .hint = "Cmd+G", .help_label = "Go to Line", .show_in_help = true },
    .{ .shortcut_id = "toggle_comment", .canonical_command_id = "toggle_line_comment", .key = "/", .modifiers = .{ .primary = true }, .hint = "Cmd+/", .help_label = "Toggle Line Comment" },
    .{ .shortcut_id = "reopen_closed_tab", .canonical_command_id = "reopen_closed_tab", .key = "t", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+T", .help_label = "Reopen Closed Tab" },
    .{ .shortcut_id = "shortcuts_help", .canonical_command_id = "toggle_shortcuts_help", .key = "/", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+/", .help_label = "Keyboard Shortcuts Help" },
    .{ .shortcut_id = "undo_edit", .canonical_command_id = "undo_edit", .key = "z", .modifiers = .{ .primary = true }, .hint = "Cmd+Z", .help_label = "Undo", .show_in_help = true },
    .{ .shortcut_id = "redo_edit", .canonical_command_id = "redo_edit", .key = "z", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+Z", .help_label = "Redo", .show_in_help = true },
    .{ .shortcut_id = "delete_last_line", .canonical_command_id = "delete_last_line", .key = "k", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+K", .help_label = "Delete Last Line" },
    .{ .shortcut_id = "next_tab", .canonical_command_id = "next_tab", .key = "tab", .modifiers = .{ .control = true }, .hint = "Ctrl+Tab", .help_label = "Next Tab" },
    .{ .shortcut_id = "prev_tab", .canonical_command_id = "prev_tab", .key = "tab", .modifiers = .{ .control = true, .shift = true }, .hint = "Ctrl+Shift+Tab", .help_label = "Previous Tab" },
    .{ .shortcut_id = "toggle_sidebar", .canonical_command_id = "toggle_sidebar", .key = "b", .modifiers = .{ .primary = true }, .hint = "Cmd+B", .help_label = "Toggle Sidebar", .show_in_help = true },
    .{ .shortcut_id = "new_untitled", .canonical_command_id = "new_untitled", .key = "n", .modifiers = .{ .primary = true }, .hint = "Cmd+N", .help_label = "New Untitled File" },
    .{ .shortcut_id = "close_active_tab", .canonical_command_id = "close_active_tab", .key = "w", .modifiers = .{ .primary = true }, .hint = "Cmd+W", .help_label = "Close Active Tab", .show_in_help = true },
    .{ .shortcut_id = "format_document", .canonical_command_id = "format_document", .key = "f", .modifiers = .{ .shift = true, .option = true }, .hint = "Shift+Alt+F", .help_label = "Format Document" },
    .{ .shortcut_id = "go_to_symbol", .canonical_command_id = "go_to_symbol", .key = "o", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+O", .help_label = "Go to Symbol" },
    .{ .shortcut_id = "go_to_definition", .canonical_command_id = "go_to_definition", .key = "d", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+D", .help_label = "Go to Definition" },
    .{ .shortcut_id = "open_folder", .canonical_command_id = "open_folder", .key = "o", .modifiers = .{ .primary = true }, .hint = "Cmd+O", .help_label = "Open Folder", .show_in_help = true },
    .{ .shortcut_id = "open_settings", .canonical_command_id = "open_settings", .key = ",", .modifiers = .{ .primary = true }, .hint = "Cmd+,", .help_label = "Open Settings", .show_in_help = true },
    .{ .shortcut_id = "save_all", .canonical_command_id = "save_all", .key = "s", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+S", .help_label = "Save All", .show_in_help = true },
    // Keep this alias: the shortcut opens Search without immediately executing a query.
    .{ .shortcut_id = "workspace_search", .canonical_command_id = "run_search", .key = "f", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+F", .help_label = "Workspace Search", .show_in_help = true },
    .{ .shortcut_id = "toggle_bottom_panel", .canonical_command_id = "toggle_bottom_panel", .key = "j", .modifiers = .{ .primary = true }, .hint = "Cmd+J", .help_label = "Toggle Bottom Panel", .show_in_help = true },
    .{ .shortcut_id = "run_selected_task", .canonical_command_id = "run_selected_task", .key = "b", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+B", .help_label = "Run Selected Task", .show_in_help = true },
    .{ .shortcut_id = "toggle_agent", .canonical_command_id = "toggle_agent", .key = "a", .modifiers = .{ .primary = true, .shift = true }, .hint = "Cmd+Shift+A", .help_label = "Toggle Agent Panel", .show_in_help = true },
    .{ .shortcut_id = "toggle_word_wrap", .canonical_command_id = "toggle_word_wrap", .key = "z", .modifiers = .{ .option = true }, .hint = "Alt+Z", .help_label = "Toggle Word Wrap", .show_in_help = true },
    .{ .shortcut_id = "escape", .canonical_command_id = "escape", .key = "escape", .target = .shell, .hint = "Escape", .help_label = "Dismiss Overlay" },
    .{ .shortcut_id = "toggle_terminal", .canonical_command_id = "toggle_terminal", .key = "`", .modifiers = .{ .control = true }, .hint = "Ctrl+`", .help_label = "Toggle Terminal", .show_in_help = true },
    .{ .shortcut_id = "save_file", .canonical_command_id = "save_file", .key = "s", .modifiers = .{ .primary = true }, .hint = "Cmd+S", .help_label = "Save File", .show_in_help = true },
};

pub const HelpItem = struct {
    id: []const u8,
    label: []const u8,
    hint: []const u8,
};

pub const help_count = blk: {
    var count: usize = 0;
    for (defaults) |binding| {
        if (binding.show_in_help) count += 1;
    }
    break :blk count;
};

pub const help_items = blk: {
    var projected: [help_count]HelpItem = undefined;
    var index: usize = 0;
    for (defaults) |binding| {
        if (!binding.show_in_help) continue;
        projected[index] = .{
            .id = binding.shortcut_id,
            .label = binding.help_label,
            .hint = binding.hint,
        };
        index += 1;
    }
    break :blk projected;
};

pub fn canonicalCommandId(shortcut_id: []const u8) ?[]const u8 {
    for (defaults) |binding| {
        if (equal(binding.shortcut_id, shortcut_id)) return binding.canonical_command_id;
    }
    return null;
}

pub fn isSupportedKey(key: []const u8) bool {
    if (key.len == 1) {
        const value = key[0];
        if (value >= 'a' and value <= 'z') return true;
        return value == '/' or value == ',' or value == '`';
    }
    return equal(key, "tab") or equal(key, "escape");
}

pub fn project(comptime Shortcut: type) [defaults.len]Shortcut {
    var projected: [defaults.len]Shortcut = undefined;
    for (defaults, 0..) |binding, index| {
        projected[index] = .{
            .id = binding.shortcut_id,
            .key = binding.key,
            .modifiers = .{
                .primary = binding.modifiers.primary,
                .control = binding.modifiers.control,
                .shift = binding.modifiers.shift,
                .option = binding.modifiers.option,
            },
        };
    }
    return projected;
}

fn equal(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left != right) return false;
    }
    return true;
}

comptime {
    @setEvalBranchQuota(5_000);
    for (defaults, 0..) |binding, index| {
        if (!isSupportedKey(binding.key)) @compileError("unsupported Native SDK shortcut key");
        if (binding.shortcut_id.len == 0 or binding.canonical_command_id.len == 0) {
            @compileError("shortcut IDs must not be empty");
        }
        for (defaults[index + 1 ..]) |other| {
            if (equal(binding.shortcut_id, other.shortcut_id)) {
                @compileError("duplicate Native SDK shortcut ID");
            }
            if (equal(binding.key, other.key) and
                binding.modifiers.primary == other.modifiers.primary and
                binding.modifiers.control == other.modifiers.control and
                binding.modifiers.shift == other.modifiers.shift and
                binding.modifiers.option == other.modifiers.option)
            {
                @compileError("duplicate Native SDK shortcut chord");
            }
        }
    }
}
