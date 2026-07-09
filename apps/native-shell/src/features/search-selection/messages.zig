//! Messages for feature.search-selection.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
