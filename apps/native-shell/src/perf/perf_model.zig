//! Performance snapshot structure — ready for real marks later.
//! Numeric fields may be mock; UI must label them as mock until measured.

pub const PerfSnapshot = struct {
    app_start_ms: u32 = 0,
    first_window_ms: u32 = 0,
    first_paint_ms: u32 = 0,
    command_palette_open_ms: u32 = 0,
    terminal_open_ms: u32 = 0,
    terminal_process_ms: u32 = 0,
    memory_rss_mb: u32 = 0,
    loaded_plugins_count: u32 = 0,
    features_registered: u32 = 0,
    features_loaded: u32 = 0,
    process_count: u32 = 0,
    process_leaked: u32 = 0,
    terminal_process_count: u32 = 0,
    lsp_process_count: u32 = 0,
    plugin_process_count: u32 = 0,
    mock: bool = true,
};
