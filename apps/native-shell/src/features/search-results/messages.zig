//! Messages for feature.search-results.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
