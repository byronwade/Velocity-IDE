//! Messages for feature.local-history.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
