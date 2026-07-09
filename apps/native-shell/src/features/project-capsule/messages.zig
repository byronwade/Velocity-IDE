//! Messages for feature.project-capsule.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
