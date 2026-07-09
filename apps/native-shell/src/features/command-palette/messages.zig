//! Messages for feature.command-palette.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
