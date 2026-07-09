//! Messages for feature.inlay-hints.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
