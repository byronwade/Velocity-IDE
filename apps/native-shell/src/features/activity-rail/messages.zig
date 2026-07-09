//! Messages for feature.activity-rail.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
