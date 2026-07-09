//! Messages for feature.folding.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
