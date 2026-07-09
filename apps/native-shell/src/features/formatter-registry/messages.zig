//! Messages for feature.formatter-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
