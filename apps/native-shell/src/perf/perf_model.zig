//! Performance snapshot structure — ready for real marks later.

pub const PerfSnapshot = struct {
    app_start_ms: u32 = 0,
    first_window_ms: u32 = 0,
    first_paint_ms: u32 = 0,
    command_palette_open_ms: u32 = 0,
    terminal_open_ms: u32 = 0,
    memory_rss_mb: u32 = 0,
    loaded_plugins_count: u32 = 0,
};
