//! Messages for feature.workspace-search.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
