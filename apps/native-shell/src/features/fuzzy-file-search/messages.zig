//! Messages for feature.fuzzy-file-search.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
