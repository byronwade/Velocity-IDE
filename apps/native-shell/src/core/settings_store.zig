//! Settings store stub — JSON settings later.
pub const Settings = struct {
    theme: []const u8 = "dark",
    telemetry: bool = false,
    plugins_locked: bool = true,
    terminal_scrollback: u32 = 2000,
    terminal_scrollback_hard_max: u32 = 10000,
};
