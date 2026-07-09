//! Messages for feature.minimap.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
