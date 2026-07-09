//! Messages for feature.recent-projects.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
