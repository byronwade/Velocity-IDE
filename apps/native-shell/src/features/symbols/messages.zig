//! Messages for feature.symbols.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
