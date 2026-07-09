//! Messages for feature.monaco-bridge.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
