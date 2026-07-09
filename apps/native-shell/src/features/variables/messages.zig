//! Messages for feature.variables.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
