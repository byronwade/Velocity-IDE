//! Editor island stub — native placeholder now; Monaco WebView later.

pub const EditorIslandState = enum { placeholder, monaco_loading, monaco_ready, native_editor };

pub const EditorIsland = struct {
    state: EditorIslandState = .placeholder,
    active_path: []const u8 = "",
};
