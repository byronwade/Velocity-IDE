//! Messages for feature.plugin-signatures.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
