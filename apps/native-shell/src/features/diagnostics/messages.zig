//! Messages for feature.diagnostics.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
