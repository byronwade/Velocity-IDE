//! Keybinding registry stub.
pub const Binding = struct {
    command_id: []const u8,
    key: []const u8,
    primary: bool = false,
};

pub const defaults = [_]Binding{
    .{ .command_id = "command_palette", .key = "k", .primary = true },
    .{ .command_id = "toggle_terminal", .key = "`" },
};
