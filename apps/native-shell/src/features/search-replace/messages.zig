//! Messages for feature.search-replace.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
