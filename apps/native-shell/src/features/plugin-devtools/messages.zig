//! Messages for feature.plugin-devtools.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
