//! Messages for feature.command-search.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
