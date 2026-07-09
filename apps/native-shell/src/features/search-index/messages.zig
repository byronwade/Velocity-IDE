//! Messages for feature.search-index.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
