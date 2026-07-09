//! Messages for feature.plugin-manifest.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
