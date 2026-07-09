//! Messages for feature.symbol-search.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
